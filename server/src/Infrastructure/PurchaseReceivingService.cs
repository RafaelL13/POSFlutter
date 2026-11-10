using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

/// <summary>Single transactional purchase/FIFO receipt primitive used by sync and web.</summary>
public sealed class PurchaseReceivingService(PosDbContext db)
{
    public async Task<Purchase> ReceiveAsync(PurchaseSyncPayload payload, SyncTenantContext tenant, CancellationToken ct)
    {
        if (payload.Lines.Count == 0 || payload.TotalCents < 0) throw new ArgumentException("Invalid purchase.");
        var existing = await db.Purchases.Include(x => x.Lines).SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId, ct);
        if (existing is not null) return existing;
        if (!await db.Suppliers.AnyAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.SupplierGlobalId && x.Active, ct)) throw new InvalidOperationException("Supplier not found.");
        var userId = await db.Users.Where(x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.UserGlobalId && x.Active)
            .Select(x => (long?)x.Id).SingleOrDefaultAsync(ct) ?? throw new InvalidOperationException("User not found.");
        var now = DateTimeOffset.UtcNow;
        var purchase = new Purchase { GlobalId=payload.GlobalId, BusinessId=tenant.BusinessId, BranchId=tenant.BranchId, DeviceId=tenant.DeviceId, UserId=userId, SupplierGlobalId=payload.SupplierGlobalId, PurchaseDate=payload.Date, Reference=payload.Reference?.Trim(), Notes=payload.Notes?.Trim(), TotalCents=payload.TotalCents, Status="Confirmed", CreatedAt=now };
        var total=0L; var stocks=new Dictionary<Guid,int>();
        foreach(var item in payload.Lines)
        {
            if(item.Quantity<=0 || item.UnitCostCents<0) throw new ArgumentException("Invalid purchase line.");
            if(!await db.Products.AnyAsync(x=>x.BusinessId==tenant.BusinessId && x.GlobalId==item.ProductGlobalId && x.Active,ct)) throw new InvalidOperationException("Product not found.");
            if(await db.InventoryLots.AnyAsync(x=>x.BusinessId==tenant.BusinessId && x.GlobalId==item.LotGlobalId,ct)) throw new ArgumentException("Inventory lot UUID is already in use.");
            var subtotal=checked((long)item.Quantity*item.UnitCostCents); total=checked(total+subtotal);
            var previous=stocks.TryGetValue(item.ProductGlobalId,out var known)?known:await db.InventoryLots.Where(x=>x.BusinessId==tenant.BusinessId&&x.BranchId==tenant.BranchId&&x.ProductGlobalId==item.ProductGlobalId&&x.Active).SumAsync(x=>(int?)x.AvailableQuantity,ct)??0;
            var next=checked(previous+item.Quantity); stocks[item.ProductGlobalId]=next;
            purchase.Lines.Add(new PurchaseLine { GlobalId=item.DetailGlobalId,ProductGlobalId=item.ProductGlobalId,Quantity=item.Quantity,UnitCostCents=item.UnitCostCents,SubtotalCents=subtotal,Lot=new InventoryLot { GlobalId=item.LotGlobalId,BusinessId=tenant.BusinessId,BranchId=tenant.BranchId,ProductGlobalId=item.ProductGlobalId,PurchaseLineGlobalId=item.DetailGlobalId,EntryDate=payload.Date,InitialQuantity=item.Quantity,AvailableQuantity=item.Quantity,UnitCostCents=item.UnitCostCents,Active=true,CreatedAt=now }});
            db.InventoryMovements.Add(new InventoryMovement { GlobalId=Guid.NewGuid(),BusinessId=tenant.BusinessId,BranchId=tenant.BranchId,ProductGlobalId=item.ProductGlobalId,MovementDate=payload.Date,Type="Purchase",QuantityDelta=item.Quantity,PreviousStock=previous,NewStock=next,ReferenceGlobalId=payload.GlobalId,UserId=userId,DeviceId=tenant.DeviceId,Notes=payload.Reference?.Trim() });
        }
        if(total!=payload.TotalCents) throw new ArgumentException("Purchase total does not equal the sum of lines.");
        db.Purchases.Add(purchase); return purchase;
    }
}
