using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class TenantReadService(PosDbContext db)
{
    private readonly PosDbContext _db = db;

    private async Task<BackendReadPermission> AuthorizeAsync(
        SyncTenantContext tenant,
        BackendReadCapability capability,
        CancellationToken cancellationToken)
    {
        var permission = BackendReadAuthorization.Require(tenant, capability);
        var valid = await (
            from business in _db.Businesses.AsNoTracking()
            join branch in _db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
            join device in _db.Devices.AsNoTracking() on branch.Id equals device.BranchId
            join user in _db.Users.AsNoTracking() on business.Id equals user.BusinessId
            where business.Id == tenant.BusinessId &&
                  business.GlobalId == tenant.BusinessGlobalId &&
                  business.Active &&
                  branch.Id == tenant.BranchId &&
                  branch.GlobalId == tenant.BranchGlobalId &&
                  branch.Active &&
                  device.Id == tenant.DeviceId &&
                  device.GlobalId == tenant.DeviceGlobalId &&
                  device.Active &&
                  device.Mode == tenant.DeviceMode &&
                  user.Id == tenant.UserId &&
                  user.GlobalId == tenant.UserGlobalId &&
                  user.Active &&
                  user.Role == tenant.Role
            select business.Id).AnyAsync(cancellationToken);
        if (!valid)
        {
            throw new UnauthorizedAccessException("Tenant context is not active.");
        }

        return permission;
    }

    private static IQueryable<Sale> ScopeSales(
        IQueryable<Sale> query,
        SyncTenantContext tenant,
        BackendReadPermission permission) => permission switch
        {
            BackendReadPermission.OwnOnly => query.Where(x =>
                x.BranchId == tenant.BranchId && x.UserId == tenant.UserId),
            BackendReadPermission.Branch => query.Where(x =>
                x.BranchId == tenant.BranchId),
            _ => query
        };

    public async Task<object> DashboardAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.SalesRead,
            cancellationToken);
        var day = new DateTimeOffset(DateTime.UtcNow.Date, TimeSpan.Zero);
        var salesQuery = ScopeSales(
            _db.Sales.AsNoTracking().Where(x =>
                x.BusinessId == tenant.BusinessId &&
                x.Status == "Confirmed"),
            tenant,
            permission);
        var operationalRows = await salesQuery
            .Select(x => new { x.SaleDateTime, x.TotalCents })
            .ToListAsync(cancellationToken);
        var todayOperational = operationalRows
            .Where(x => x.SaleDateTime >= day)
            .ToList();
        var lastSyncAt = await _db.Devices.AsNoTracking()
            .Where(x => x.Id == tenant.DeviceId)
            .Select(x => x.LastSyncAt)
            .SingleAsync(cancellationToken);
        var salesCents = todayOperational.Sum(x => x.TotalCents);
        var operations = todayOperational.Count;

        if (!Can(tenant, BackendReadCapability.ViewProfit))
        {
            if (Can(tenant, BackendReadCapability.ViewExpenses))
            {
                var expenseRows = await ScopedExpenses(tenant)
                    .Select(x => new { x.ExpenseDate, x.AmountCents })
                    .ToListAsync(cancellationToken);
                var expenses = expenseRows
                    .Where(x => x.ExpenseDate >= day)
                    .Sum(x => x.AmountCents);
                return new { salesCents, operations, expensesCents = expenses, lastSyncAt };
            }

            return new { salesCents, operations, lastSyncAt };
        }

        var financialRows = await salesQuery
            .Select(x => new
            {
                x.SaleDateTime,
                x.FifoCostCents,
                x.GrossProfitCents
            })
            .ToListAsync(cancellationToken);
        var todayFinancial = financialRows.Where(x => x.SaleDateTime >= day).ToList();
        var expenseFinancialRows = await _db.Expenses.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId)
            .Select(x => new { x.ExpenseDate, x.AmountCents })
            .ToListAsync(cancellationToken);
        var expensesCents = expenseFinancialRows
            .Where(x => x.ExpenseDate >= day)
            .Sum(x => x.AmountCents);
        var fifoCostCents = todayFinancial.Sum(x => x.FifoCostCents);
        var grossProfitCents = todayFinancial.Sum(x => x.GrossProfitCents);
        var resultCents = grossProfitCents - expensesCents;
        var marginBasisPoints = salesCents == 0
            ? 0
            : grossProfitCents * 10000 / salesCents;
        return new
        {
            salesCents,
            operations,
            fifoCostCents,
            grossProfitCents,
            marginBasisPoints,
            expensesCents,
            resultCents,
            lastSyncAt
        };
    }

    public async Task<IReadOnlyList<object>> ProductsAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.ProductsRead, cancellationToken);
        return await _db.Products.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId)
            .OrderBy(x => x.Name)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Code,
                x.Barcode,
                x.Name,
                x.Presentation,
                x.SalePriceCents,
                x.MinimumStock,
                x.Active,
                x.ServerVersion
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> CategoriesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.CategoriesRead, cancellationToken);
        return await _db.Categories.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId)
            .OrderBy(x => x.Name)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Name,
                x.Description,
                x.Active,
                x.ServerVersion
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> SuppliersAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.SuppliersRead, cancellationToken);
        return await _db.Suppliers.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId)
            .OrderBy(x => x.Name)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Name,
                x.ContactName,
                x.Phone,
                x.Email,
                x.Active,
                x.ServerVersion
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> SalesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.SalesRead,
            cancellationToken);
        var query = ScopeSales(
            _db.Sales.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId),
            tenant,
            permission);
        if (!Can(tenant, BackendReadCapability.ViewProfit))
        {
            return await query.OrderByDescending(x => x.Id)
                .Take(500)
                .Select(x => (object)new
                {
                    x.GlobalId,
                    x.Folio,
                    x.SaleDateTime,
                    x.TotalCents,
                    x.PaymentMethod,
                    x.Status,
                    x.CancelledAt,
                    x.CancellationReason
                })
                .ToListAsync(cancellationToken);
        }

        return await query.OrderByDescending(x => x.Id)
            .Take(500)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Folio,
                x.SaleDateTime,
                x.TotalCents,
                x.FifoCostCents,
                x.GrossProfitCents,
                x.PaymentMethod,
                x.Status,
                x.CancelledAt,
                x.CancellationReason
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<object?> SaleAsync(
        SyncTenantContext tenant,
        Guid globalId,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.SalesRead,
            cancellationToken);
        var query = ScopeSales(
            _db.Sales.AsNoTracking().Where(x =>
                x.BusinessId == tenant.BusinessId && x.GlobalId == globalId),
            tenant,
            permission);
        if (!Can(tenant, BackendReadCapability.ViewProfit))
        {
            return await query.Select(x => (object)new
            {
                x.GlobalId,
                x.Folio,
                x.SaleDateTime,
                x.TotalCents,
                x.Status
            }).SingleOrDefaultAsync(cancellationToken);
        }

        return await query.Select(x => (object)new
        {
            x.GlobalId,
            x.Folio,
            x.SaleDateTime,
            x.TotalCents,
            x.FifoCostCents,
            x.GrossProfitCents,
            x.Status
        }).SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> PurchasesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.PurchasesRead,
            cancellationToken);
        var query = _db.Purchases.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        if (permission == BackendReadPermission.Branch)
        {
            query = query.Where(x => x.BranchId == tenant.BranchId);
        }

        if (!Can(tenant, BackendReadCapability.ViewPurchaseCost))
        {
            return await query.OrderByDescending(x => x.Id)
                .Take(500)
                .Select(x => (object)new
                {
                    x.GlobalId,
                    x.SupplierGlobalId,
                    x.PurchaseDate,
                    x.Status
                })
                .ToListAsync(cancellationToken);
        }

        return await query.OrderByDescending(x => x.Id)
            .Take(500)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.SupplierGlobalId,
                x.PurchaseDate,
                x.TotalCents,
                x.Status
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> InventoryAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.InventoryAvailabilityRead,
            cancellationToken);
        var query = _db.InventoryLots.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        if (permission is BackendReadPermission.Branch or BackendReadPermission.OwnOnly)
        {
            query = query.Where(x => x.BranchId == tenant.BranchId);
        }

        if (!Can(tenant, BackendReadCapability.ViewInventoryValue))
        {
            return await query.GroupBy(x => x.ProductGlobalId)
                .Select(group => (object)new
                {
                    productGlobalId = group.Key,
                    stock = group.Sum(x => x.AvailableQuantity)
                })
                .ToListAsync(cancellationToken);
        }

        return await query.GroupBy(x => x.ProductGlobalId)
            .Select(group => (object)new
            {
                productGlobalId = group.Key,
                stock = group.Sum(x => x.AvailableQuantity),
                inventoryValueCents = group.Sum(x =>
                    (long)x.AvailableQuantity * x.UnitCostCents)
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> LotsAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.InventoryLotsRead,
            cancellationToken);
        var query = _db.InventoryLots.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        if (permission == BackendReadPermission.Branch)
        {
            query = query.Where(x => x.BranchId == tenant.BranchId);
        }

        if (!Can(tenant, BackendReadCapability.ViewFifoHistoricalCost))
        {
            return await query.OrderBy(x => x.Id)
                .Select(x => (object)new
                {
                    x.GlobalId,
                    x.ProductGlobalId,
                    x.EntryDate,
                    x.InitialQuantity,
                    x.AvailableQuantity,
                    x.Active
                })
                .ToListAsync(cancellationToken);
        }

        return await query.OrderBy(x => x.Id)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.ProductGlobalId,
                x.EntryDate,
                x.InitialQuantity,
                x.AvailableQuantity,
                x.UnitCostCents,
                x.Active
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> ExpensesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.ExpensesRead,
            cancellationToken);
        var query = _db.Expenses.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        if (permission == BackendReadPermission.Branch)
        {
            query = query.Where(x => x.BranchId == tenant.BranchId);
        }

        if (!Can(tenant, BackendReadCapability.ViewExpenses))
        {
            return await query.OrderByDescending(x => x.Id)
                .Take(500)
                .Select(x => (object)new
                {
                    x.GlobalId,
                    x.ExpenseDate,
                    x.Concept,
                    x.Category,
                    x.PaymentMethod
                })
                .ToListAsync(cancellationToken);
        }

        return await query.OrderByDescending(x => x.Id)
            .Take(500)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.ExpenseDate,
                x.Concept,
                x.Category,
                x.AmountCents,
                x.PaymentMethod
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> CashAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.CashRead,
            cancellationToken);
        var query = _db.CashSessions.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        query = permission switch
        {
            BackendReadPermission.OwnOnly => query.Where(x =>
                x.BranchId == tenant.BranchId && x.UserId == tenant.UserId),
            BackendReadPermission.Branch => query.Where(x =>
                x.BranchId == tenant.BranchId),
            _ => query
        };
        if (!Can(tenant, BackendReadCapability.FinancialReportsRead))
        {
            return await query.OrderByDescending(x => x.Id)
                .Take(200)
                .Select(x => (object)new
                {
                    x.GlobalId,
                    x.OpenedAt,
                    x.OpeningBalanceCents,
                    x.Status,
                    x.ClosedAt
                })
                .ToListAsync(cancellationToken);
        }

        return await query.OrderByDescending(x => x.Id)
            .Take(200)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.OpenedAt,
                x.OpeningBalanceCents,
                x.Status,
                x.ClosedAt,
                x.CountedCashCents,
                x.ExpectedCashCents,
                x.DifferenceCents
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> UsersAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.UsersRead, cancellationToken);
        return await _db.Users.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId)
            .OrderBy(x => x.Name)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Name,
                x.Username,
                x.Role,
                x.Active,
                x.ServerVersion
            })
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> DevicesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.DevicesRead, cancellationToken);
        return await (
            from device in _db.Devices.AsNoTracking()
            join branch in _db.Branches.AsNoTracking() on device.BranchId equals branch.Id
            where branch.BusinessId == tenant.BusinessId
            orderby device.Name
            select (object)new
            {
                device.GlobalId,
                BranchGlobalId = branch.GlobalId,
                device.Name,
                device.Mode,
                device.Active,
                device.LastSyncAt,
                device.ServerVersion
            }).ToListAsync(cancellationToken);
    }

    public async Task<object> BusinessAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        await AuthorizeAsync(tenant, BackendReadCapability.BusinessRead, cancellationToken);
        return await _db.Businesses.AsNoTracking()
            .Where(x => x.Id == tenant.BusinessId)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Name,
                x.Active,
                x.ServerVersion
            })
            .SingleAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<object>> BranchesAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var permission = await AuthorizeAsync(
            tenant,
            BackendReadCapability.BranchesRead,
            cancellationToken);
        var query = _db.Branches.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId);
        if (permission == BackendReadPermission.Branch)
        {
            query = query.Where(x => x.Id == tenant.BranchId);
        }

        return await query.OrderBy(x => x.Name)
            .Select(x => (object)new
            {
                x.GlobalId,
                x.Name,
                x.Active,
                x.ServerVersion
            })
            .ToListAsync(cancellationToken);
    }

    private IQueryable<Expense> ScopedExpenses(SyncTenantContext tenant) =>
        _db.Expenses.AsNoTracking().Where(x =>
            x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId);

    private static bool Can(
        SyncTenantContext tenant,
        BackendReadCapability capability) =>
        BackendReadAuthorization.PermissionFor(
            tenant.Role,
            tenant.DeviceMode,
            capability) != BackendReadPermission.None;
}
