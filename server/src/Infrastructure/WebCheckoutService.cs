using System.Data;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

// Isolated candidate extension for the REAL central server; not active until explicitly wired.
// Serializable transaction protects stock reads and writes against concurrent checkouts.
public sealed class WebCheckoutService(PosDbContext db)
{
    public async Task<WebCheckoutResult> CheckoutAsync(WebCheckoutRequest request,
        SyncTenantContext tenant, CancellationToken ct)
    {
        Validate(request);
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            var activeContext = await (
                from business in db.Businesses
                join branch in db.Branches on business.Id equals branch.BusinessId
                join device in db.Devices on branch.Id equals device.BranchId
                join user in db.Users on business.Id equals user.BusinessId
                where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active
                  && branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active
                  && device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active
                  && device.Mode == "PointOfSale"
                  && user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active
                  && user.Role == tenant.Role
                select user.Id).AnyAsync(ct);
            if (!activeContext || tenant.Role is not ("Administrator" or "Manager" or "Supervisor" or "Seller"))
                throw new UnauthorizedAccessException("Checkout identity, role or device is not authorized.");

            var existing = await db.Sales.AsNoTracking().SingleOrDefaultAsync(x =>
                x.BusinessId == tenant.BusinessId && x.IdempotencyKey == request.IdempotencyKey, ct);
            if (existing is not null)
            {
                var sameLines = await db.SaleLines.AsNoTracking()
                    .Where(x => x.SaleId == existing.Id)
                    .Select(x => new { x.ProductGlobalId, x.Quantity }).ToListAsync(ct);
                var samePayments = await db.SalePayments.AsNoTracking()
                    .Where(x => x.SaleId == existing.Id)
                    .Select(x => new { x.Method, x.AmountCents }).ToListAsync(ct);
                // A retry is valid only for the same actor, device, branch and full payment intent.
                // This also prevents an unrelated session within a tenant from retrieving a receipt.
                var originalCashCents = samePayments
                    .Where(x => x.Method == "Cash").Sum(x => x.AmountCents);
                var tenderMatches = originalCashCents == 0
                    ? request.ReceivedCashCents is null && existing.ReceivedCents is null && existing.ChangeCents == 0
                    : request.ReceivedCashCents == existing.ReceivedCents &&
                      existing.ChangeCents == checked(existing.ReceivedCents.GetValueOrDefault() - originalCashCents);
                if (existing.BranchId != tenant.BranchId || existing.DeviceId != tenant.DeviceId ||
                    existing.UserId != tenant.UserId || !tenderMatches ||
                    sameLines.Count != request.Lines.Count || samePayments.Count != request.Payments.Count ||
                    request.Lines.Any(x => !sameLines.Any(y => y.ProductGlobalId == x.ProductGlobalId && y.Quantity == x.Quantity)) ||
                    request.Payments.Any(x => !samePayments.Any(y => y.Method == x.Method && y.AmountCents == x.AmountCents)))
                    throw new InvalidOperationException("Idempotency key reused with different checkout content.");
                await tx.CommitAsync(ct);
                return new(existing.GlobalId, existing.Folio, existing.TotalCents,
                    existing.FifoCostCents, true, existing.SaleDateTime);
            }

            var now = DateTimeOffset.UtcNow;
            long subtotal = 0, fifoCost = 0;
            var saleId = Guid.NewGuid();
            var sale = new Sale
            {
                GlobalId = saleId, IdempotencyKey = request.IdempotencyKey,
                BusinessId = tenant.BusinessId, BranchId = tenant.BranchId,
                DeviceId = tenant.DeviceId, UserId = tenant.UserId,
                Folio = $"WEB-{saleId:N}", SaleDateTime = now, CreatedAt = now,
                Status = "Confirmed", DiscountCents = 0
            };
            foreach (var requested in request.Lines.OrderBy(x => x.ProductGlobalId))
            {
                var product = await db.Products.AsNoTracking().SingleOrDefaultAsync(x =>
                    x.BusinessId == tenant.BusinessId && x.GlobalId == requested.ProductGlobalId && x.Active, ct)
                    ?? throw new InvalidOperationException("Product is inactive or missing.");
                var lineTotal = checked(product.SalePriceCents * requested.Quantity);
                subtotal = checked(subtotal + lineTotal);
                var lots = await db.InventoryLots
                    .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId
                        && x.ProductGlobalId == requested.ProductGlobalId && x.Active && x.AvailableQuantity > 0)
                    .OrderBy(x => x.EntryDate).ThenBy(x => x.Id).ToListAsync(ct);
                var previousStock = lots.Sum(x => (long)x.AvailableQuantity);
                if (previousStock < requested.Quantity)
                    throw new InvalidOperationException("Insufficient stock.");
                var line = new SaleLine
                {
                    GlobalId = Guid.NewGuid(), ProductGlobalId = requested.ProductGlobalId,
                    Quantity = requested.Quantity, UnitPriceCents = product.SalePriceCents,
                    TotalCents = lineTotal
                };
                var remaining = requested.Quantity;
                foreach (var lot in lots)
                {
                    if (remaining == 0) break;
                    var taken = Math.Min(remaining, lot.AvailableQuantity);
                    var cost = checked((long)taken * lot.UnitCostCents);
                    lot.AvailableQuantity -= taken;
                    remaining -= taken;
                    line.FifoCostCents = checked(line.FifoCostCents + cost);
                    line.Lots.Add(new SaleLotAllocation
                    {
                        GlobalId = Guid.NewGuid(), InventoryLotGlobalId = lot.GlobalId,
                        Quantity = taken, UnitCostCents = lot.UnitCostCents, TotalCostCents = cost
                    });
                }
                if (remaining != 0) throw new InvalidOperationException("Stock changed during checkout.");
                fifoCost = checked(fifoCost + line.FifoCostCents);
                sale.Lines.Add(line);
                db.InventoryMovements.Add(new InventoryMovement
                {
                    GlobalId = Guid.NewGuid(), BusinessId = tenant.BusinessId,
                    BranchId = tenant.BranchId, ProductGlobalId = requested.ProductGlobalId,
                    MovementDate = now, Type = "Sale", QuantityDelta = -requested.Quantity,
                    PreviousStock = checked((int)previousStock),
                    NewStock = checked((int)(previousStock - requested.Quantity)),
                    ReferenceGlobalId = saleId, UserId = tenant.UserId, DeviceId = tenant.DeviceId
                });
            }
            if (subtotal <= 0) throw new ArgumentException("Sale total must be positive.");
            var paymentsTotal = request.Payments.Aggregate(0L, (current, payment) => checked(current + payment.AmountCents));
            if (paymentsTotal != subtotal) throw new ArgumentException("Payments must equal server-calculated total.");
            var cash = request.Payments.Where(x => x.Method == "Cash")
                .Aggregate(0L, (total, payment) => checked(total + payment.AmountCents));
            if (cash == 0 && request.ReceivedCashCents is not null)
                throw new ArgumentException("Cash tender supplied without cash payment.");
            if (cash > 0 && (request.ReceivedCashCents is null || request.ReceivedCashCents < cash))
                throw new ArgumentException("Cash tender is insufficient.");
            sale.ReceivedCents = cash > 0 ? request.ReceivedCashCents : null;
            sale.ChangeCents = cash > 0 ? checked(request.ReceivedCashCents!.Value - cash) : 0;
            sale.SubtotalCents = subtotal;
            sale.TotalCents = subtotal;
            sale.FifoCostCents = fifoCost;
            sale.GrossProfitCents = checked(subtotal - fifoCost);
            sale.PaymentMethod = request.Payments.Count == 1 ? request.Payments[0].Method : "Mixed";
            foreach (var payment in request.Payments)
                sale.Payments.Add(new SalePayment
                {
                    GlobalId = Guid.NewGuid(), Method = payment.Method,
                    AmountCents = payment.AmountCents, CreatedAt = now
                });
            db.Sales.Add(sale);
            // NOTE: SyncChange is NOT fabricated here. Existing Android pull contracts
            // must be reused before enabling this endpoint, otherwise a partial Sale
            // payload could corrupt downstream synchronization.
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return new(saleId, sale.Folio, subtotal, fifoCost, false, now);
        }
        catch
        {
            try { await tx.RollbackAsync(CancellationToken.None); }
            catch { /* Preserve the original transaction failure. */ }
            throw;
        }
    }

    private static void Validate(WebCheckoutRequest r)
    {
        if (r.IdempotencyKey == Guid.Empty || r.Lines is null || r.Payments is null ||
            r.Lines.Count is < 1 or > 100 || r.Payments.Count is < 1 or > 3 ||
            r.Lines.Any(x => x.ProductGlobalId == Guid.Empty || x.Quantity is < 1 or > 100000) ||
            r.Lines.Select(x => x.ProductGlobalId).Distinct().Count() != r.Lines.Count ||
            r.Payments.Any(x => x.Method is not ("Cash" or "Card" or "Transfer") || x.AmountCents <= 0) ||
            r.Payments.Select(x => x.Method).Distinct().Count() != r.Payments.Count)
            throw new ArgumentException("Invalid checkout request.");
    }
}
