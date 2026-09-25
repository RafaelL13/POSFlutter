using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class CentralInventoryTransferService(PosDbContext db) : ICentralInventoryTransferService
{
    private readonly PosDbContext _db = db;

    public async Task<CentralTransferInResult> ReceiveAsync(
        CentralTransferInRequest request,
        CancellationToken cancellationToken)
    {
        if (request.TransferGlobalId == Guid.Empty ||
            request.BusinessGlobalId == Guid.Empty ||
            request.BranchGlobalId == Guid.Empty)
            throw new ArgumentException("Transfer, business and branch identifiers are required.");
        if (request.Lines.Count == 0)
            throw new ArgumentException("Central transfer must contain at least one line.");
        if (request.Lines.Any(x =>
            x.ProductGlobalId == Guid.Empty ||
            x.LotGlobalId == Guid.Empty ||
            x.Quantity <= 0 ||
            x.UnitCostCents < 0))
            throw new ArgumentException("Central transfer contains an invalid line.");

        var business = await _db.Businesses.AsNoTracking().SingleOrDefaultAsync(
            x => x.GlobalId == request.BusinessGlobalId && x.Active,
            cancellationToken)
            ?? throw new InvalidOperationException("Destination business does not exist or is inactive.");

        var branch = await _db.Branches.AsNoTracking().SingleOrDefaultAsync(
            x => x.BusinessId == business.Id &&
                 x.GlobalId == request.BranchGlobalId &&
                 x.Active,
            cancellationToken)
            ?? throw new InvalidOperationException("Destination branch does not exist or is inactive.");

        var existing = await _db.CentralInventoryTransferReceipts.AsNoTracking()
            .SingleOrDefaultAsync(
                x => x.BusinessId == business.Id &&
                     x.TransferGlobalId == request.TransferGlobalId,
                cancellationToken);
        if (existing is not null)
            return new CentralTransferInResult(true, true, existing.Id.ToString());

        var technicalDeviceId = await _db.Devices.AsNoTracking()
            .Where(x => x.BranchId == branch.Id && x.Active)
            .OrderBy(x => x.Id)
            .Select(x => (long?)x.Id)
            .FirstOrDefaultAsync(cancellationToken)
            ?? throw new InvalidOperationException("Destination branch has no active device for inventory audit attribution.");
        var technicalUserId = await _db.Users.AsNoTracking()
            .Where(x => x.BusinessId == business.Id && x.Active && x.Role == "Administrator")
            .OrderBy(x => x.Id)
            .Select(x => (long?)x.Id)
            .FirstOrDefaultAsync(cancellationToken)
            ?? throw new InvalidOperationException("Destination business has no active administrator for inventory audit attribution.");

        if (request.Lines.Select(x => x.LotGlobalId).Distinct().Count() != request.Lines.Count)
            throw new ArgumentException("Central transfer contains duplicate lot identifiers.");

        var productIds = request.Lines.Select(x => x.ProductGlobalId).Distinct().ToArray();
        var existingProducts = await _db.Products.AsNoTracking()
            .Where(x => x.BusinessId == business.Id && x.Active && productIds.Contains(x.GlobalId))
            .Select(x => x.GlobalId)
            .ToListAsync(cancellationToken);
        if (existingProducts.Count != productIds.Length)
            throw new InvalidOperationException("One or more destination products do not exist or are inactive.");

        var lotIds = request.Lines.Select(x => x.LotGlobalId).ToArray();
        if (await _db.InventoryLots.AsNoTracking().AnyAsync(
            x => x.BusinessId == business.Id && lotIds.Contains(x.GlobalId),
            cancellationToken))
            throw new InvalidOperationException("One or more central lot identifiers already exist in POS inventory.");

        await using var transaction = await _db.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            var stocks = new Dictionary<Guid, int>();
            foreach (var line in request.Lines)
            {
                if (!stocks.TryGetValue(line.ProductGlobalId, out var previousStock))
                {
                    previousStock = await _db.InventoryLots.AsNoTracking()
                        .Where(x => x.BusinessId == business.Id &&
                                    x.BranchId == branch.Id &&
                                    x.ProductGlobalId == line.ProductGlobalId &&
                                    x.Active)
                        .SumAsync(x => (int?)x.AvailableQuantity, cancellationToken) ?? 0;
                }

                var newStock = checked(previousStock + line.Quantity);
                stocks[line.ProductGlobalId] = newStock;

                _db.InventoryLots.Add(new InventoryLot
                {
                    GlobalId = line.LotGlobalId,
                    BusinessId = business.Id,
                    BranchId = branch.Id,
                    ProductGlobalId = line.ProductGlobalId,
                    PurchaseLineGlobalId = null,
                    EntryDate = request.Date,
                    InitialQuantity = line.Quantity,
                    AvailableQuantity = line.Quantity,
                    UnitCostCents = line.UnitCostCents,
                    Active = true,
                    CreatedAt = DateTimeOffset.UtcNow
                });

                _db.InventoryMovements.Add(new InventoryMovement
                {
                    GlobalId = Guid.NewGuid(),
                    BusinessId = business.Id,
                    BranchId = branch.Id,
                    ProductGlobalId = line.ProductGlobalId,
                    MovementDate = request.Date,
                    Type = "CentralTransferIn",
                    QuantityDelta = line.Quantity,
                    PreviousStock = previousStock,
                    NewStock = newStock,
                    ReferenceGlobalId = request.TransferGlobalId,
                    UserId = technicalUserId,
                    DeviceId = technicalDeviceId,
                    Notes = "InventarioCentral"
                });
            }

            var receipt = new CentralInventoryTransferReceipt
            {
                TransferGlobalId = request.TransferGlobalId,
                BusinessId = business.Id,
                BranchId = branch.Id,
                ReceivedAt = DateTimeOffset.UtcNow
            };
            _db.CentralInventoryTransferReceipts.Add(receipt);
            await _db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return new CentralTransferInResult(true, false, receipt.Id.ToString());
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }
}
