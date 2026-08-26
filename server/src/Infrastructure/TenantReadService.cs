using Microsoft.EntityFrameworkCore;
using Pos.Application;

namespace Pos.Infrastructure;

public sealed class TenantReadService(PosDbContext db)
{
    private readonly PosDbContext _db=db;
    private async Task EnsureAsync(SyncTenantContext t,CancellationToken ct)
    {
        var valid=await (from b in _db.Businesses.AsNoTracking()
                         join br in _db.Branches.AsNoTracking() on b.Id equals br.BusinessId
                         join d in _db.Devices.AsNoTracking() on br.Id equals d.BranchId
                         join u in _db.Users.AsNoTracking() on b.Id equals u.BusinessId
                         where b.Id==t.BusinessId && b.GlobalId==t.BusinessGlobalId && b.Active &&
                               br.Id==t.BranchId && br.GlobalId==t.BranchGlobalId && br.Active &&
                               d.Id==t.DeviceId && d.GlobalId==t.DeviceGlobalId && d.Active &&
                               u.Id==t.UserId && u.GlobalId==t.UserGlobalId && u.Active
                         select b.Id).AnyAsync(ct);
        if(!valid)throw new UnauthorizedAccessException("Tenant context is not active.");
    }
    public async Task<object> DashboardAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);var day=new DateTimeOffset(DateTime.UtcNow.Date,TimeSpan.Zero);var sales=await _db.Sales.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId&&x.SaleDateTime>=day&&x.Status=="Confirmed").ToListAsync(ct);var expenses=await _db.Expenses.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId&&x.ExpenseDate>=day).SumAsync(x=>(long?)x.AmountCents,ct)??0;return new{salesCents=sales.Sum(x=>x.TotalCents),operations=sales.Count,fifoCostCents=sales.Sum(x=>x.FifoCostCents),grossProfitCents=sales.Sum(x=>x.GrossProfitCents),expensesCents=expenses,resultCents=sales.Sum(x=>x.GrossProfitCents)-expenses,lastSyncAt=await _db.Devices.Where(x=>x.Id==t.DeviceId).Select(x=>x.LastSyncAt).SingleAsync(ct)};}
    public async Task<IReadOnlyList<object>> ProductsAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Products.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderBy(x=>x.Name).Select(x=>(object)new{x.GlobalId,x.Code,x.Barcode,x.Name,x.Presentation,x.SalePriceCents,x.MinimumStock,x.Active,x.ServerVersion}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> CategoriesAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Categories.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderBy(x=>x.Name).Select(x=>(object)new{x.GlobalId,x.Name,x.Description,x.Active,x.ServerVersion}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> SuppliersAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Suppliers.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderBy(x=>x.Name).Select(x=>(object)new{x.GlobalId,x.Name,x.ContactName,x.Phone,x.Email,x.Active,x.ServerVersion}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> SalesAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Sales.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderByDescending(x=>x.SaleDateTime).Take(500).Select(x=>(object)new{x.GlobalId,x.Folio,x.SaleDateTime,x.TotalCents,x.FifoCostCents,x.GrossProfitCents,x.PaymentMethod,x.Status,x.CancelledAt,x.CancellationReason}).ToListAsync(ct);}
    public async Task<object?> SaleAsync(SyncTenantContext t,Guid globalId,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Sales.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId&&x.GlobalId==globalId).Select(x=>(object)new{x.GlobalId,x.Folio,x.SaleDateTime,x.TotalCents,x.FifoCostCents,x.GrossProfitCents,x.Status}).SingleOrDefaultAsync(ct);}
    public async Task<IReadOnlyList<object>> PurchasesAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Purchases.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderByDescending(x=>x.PurchaseDate).Take(500).Select(x=>(object)new{x.GlobalId,x.SupplierGlobalId,x.PurchaseDate,x.TotalCents,x.Status}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> InventoryAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.InventoryLots.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).GroupBy(x=>x.ProductGlobalId).Select(g=>(object)new{productGlobalId=g.Key,stock=g.Sum(x=>x.AvailableQuantity),inventoryValueCents=g.Sum(x=>(long)x.AvailableQuantity*x.UnitCostCents)}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> LotsAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.InventoryLots.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderBy(x=>x.EntryDate).Select(x=>(object)new{x.GlobalId,x.ProductGlobalId,x.EntryDate,x.InitialQuantity,x.AvailableQuantity,x.UnitCostCents,x.Active}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> ExpensesAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Expenses.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderByDescending(x=>x.ExpenseDate).Take(500).Select(x=>(object)new{x.GlobalId,x.ExpenseDate,x.Concept,x.Category,x.AmountCents,x.PaymentMethod}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> CashAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.CashSessions.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderByDescending(x=>x.OpenedAt).Take(200).Select(x=>(object)new{x.GlobalId,x.OpenedAt,x.OpeningBalanceCents,x.Status,x.ClosedAt,x.CountedCashCents,x.ExpectedCashCents,x.DifferenceCents}).ToListAsync(ct);}
    public async Task<IReadOnlyList<object>> UsersAsync(SyncTenantContext t,CancellationToken ct){await EnsureAsync(t,ct);return await _db.Users.AsNoTracking().Where(x=>x.BusinessId==t.BusinessId).OrderBy(x=>x.Name).Select(x=>(object)new{x.GlobalId,x.Name,x.Username,x.Role,x.Active,x.ServerVersion}).ToListAsync(ct);}
}
