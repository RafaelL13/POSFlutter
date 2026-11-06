using System.Data;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed record WebSaleCancellationRequest(Guid SaleGlobalId, string Reason);
public sealed record WebSaleCancellationResult(Guid SaleGlobalId, bool AlreadyCancelled);

// Web counterpart of SyncService.ApplySaleCancellationAsync. Keep its FIFO restoration and
// cancellation event shape aligned with the Android synchronization contract.
public sealed class WebSaleCancellationService(PosDbContext db)
{
    public async Task<WebSaleCancellationResult> CancelAsync(WebSaleCancellationRequest request, SyncTenantContext tenant, CancellationToken ct)
    {
        if (request.SaleGlobalId == Guid.Empty || string.IsNullOrWhiteSpace(request.Reason) || request.Reason.Trim().Length > 240)
            throw new ArgumentException("Invalid cancellation.");
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            if (tenant.Role is not ("Administrator" or "Manager")) throw new UnauthorizedAccessException();
            // Revalidate persisted tenant identity inside the cancellation transaction.
            // A previously authenticated session must not authorize a revoked actor.
            var activeContext = await (
                from business in db.Businesses
                join branch in db.Branches on business.Id equals branch.BusinessId
                join device in db.Devices on branch.Id equals device.BranchId
                join user in db.Users on business.Id equals user.BusinessId
                where business.Id == tenant.BusinessId
                   && business.GlobalId == tenant.BusinessGlobalId
                   && business.Active
                   && branch.Id == tenant.BranchId
                   && branch.GlobalId == tenant.BranchGlobalId
                   && branch.Active
                   && device.Id == tenant.DeviceId
                   && device.GlobalId == tenant.DeviceGlobalId
                   && device.Active
                   && device.Mode == "PointOfSale"
                   && user.Id == tenant.UserId
                   && user.GlobalId == tenant.UserGlobalId
                   && user.Active
                   && user.Role == tenant.Role
                select user.Id).AnyAsync(ct);

            if (!activeContext)
                throw new UnauthorizedAccessException("Cancellation identity has been revoked.");
            var sale = await db.Sales.Include(x => x.Lines).ThenInclude(x => x.Lots).Include(x => x.Payments)
                .SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == request.SaleGlobalId, ct)
                ?? throw new KeyNotFoundException();
            if (sale.BranchId != tenant.BranchId || sale.DeviceId != tenant.DeviceId || sale.Status is not ("Confirmed" or "Cancelled")) throw new InvalidOperationException();
            if (sale.Status == "Cancelled") { await tx.CommitAsync(ct); return new(sale.GlobalId, true); }
            // Card/transfer refunds need an external settlement workflow. Fail closed rather than
            // misrepresenting money as returned. Cash requires the original still-open session.
            if (sale.Payments.Any(x => x.Method != "Cash")) throw new InvalidOperationException("Refund settlement is required.");
            var cashSessionId = sale.Payments.Select(x => x.CashSessionId).Distinct().SingleOrDefault();
            var cashSession = cashSessionId is null ? null : await db.CashSessions.SingleOrDefaultAsync(x => x.Id == cashSessionId && x.BusinessId == tenant.BusinessId && x.Status == "Open", ct);
            if (cashSession is null) throw new InvalidOperationException("Cash refund requires its original open session.");
            var now = DateTimeOffset.UtcNow; var reason = request.Reason.Trim();
            foreach (var line in sale.Lines)
            {
                var previous = await db.InventoryLots.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == sale.BranchId && x.ProductGlobalId == line.ProductGlobalId && x.Active).SumAsync(x => (int?)x.AvailableQuantity, ct) ?? 0;
                foreach (var allocation in line.Lots)
                {
                    var lot = await db.InventoryLots.SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == allocation.InventoryLotGlobalId, ct) ?? throw new InvalidOperationException("Allocated lot is missing.");
                    if (lot.AvailableQuantity + allocation.Quantity > lot.InitialQuantity) throw new InvalidOperationException("Lot restoration exceeds original quantity.");
                    lot.AvailableQuantity += allocation.Quantity;
                }
                db.InventoryMovements.Add(new InventoryMovement { GlobalId=Guid.NewGuid(), BusinessId=tenant.BusinessId, BranchId=sale.BranchId, ProductGlobalId=line.ProductGlobalId, MovementDate=now, Type="Cancellation", QuantityDelta=line.Quantity, PreviousStock=previous, NewStock=checked(previous+line.Quantity), ReferenceGlobalId=sale.GlobalId, UserId=tenant.UserId, DeviceId=tenant.DeviceId, Notes=reason });
            }
            var refund = sale.Payments.Sum(x => x.AmountCents);
            db.CashMovements.Add(new CashMovement { GlobalId=Guid.NewGuid(), BusinessId=tenant.BusinessId, UserId=tenant.UserId, CashSessionId=cashSession.Id, MovementDate=now, Type="ManualOut", AmountCents=-refund, Notes=$"Sale cancellation {sale.Folio}: {reason}" });
            sale.Status="Cancelled"; sale.CancelledAt=now; sale.CancellationReason=reason; sale.CancelledByUserId=tenant.UserId;
            var payload = new SaleCancelSyncPayload(sale.GlobalId, tenant.DeviceGlobalId, tenant.UserGlobalId, now, reason);
            db.SyncChanges.Add(new SyncChange { BusinessId=tenant.BusinessId, EntityType="Sale", EntityGlobalId=sale.GlobalId, Operation="Cancel", Version=1, PayloadJson=JsonSerializer.Serialize(payload), CreatedAt=now });
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new(sale.GlobalId, false);
        }
        catch { try { await tx.RollbackAsync(CancellationToken.None); } catch { } throw; }
    }
}
