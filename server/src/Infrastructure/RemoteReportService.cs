using Microsoft.EntityFrameworkCore;
using Pos.Application;

namespace Pos.Infrastructure;

public sealed class RemoteReportService(PosDbContext db)
{
    private const string Confirmed = "Confirmed";
    private const string Cancelled = "Cancelled";
    private const double StableThresholdPercent = 5.0;
    private readonly PosDbContext _db = db;

    private async Task EnsureAsync(SyncTenantContext tenant,CancellationToken ct)
    {
        BackendReadAuthorization.Require(
            tenant,
            BackendReadCapability.FinancialReportsRead);
        var valid = await (
            from business in _db.Businesses.AsNoTracking()
            join branch in _db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
            join device in _db.Devices.AsNoTracking() on branch.Id equals device.BranchId
            join user in _db.Users.AsNoTracking() on business.Id equals user.BusinessId
            where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active
                && branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active
                && device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active
                && device.Mode == tenant.DeviceMode
                && user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active
                && user.Role == tenant.Role
            select business.Id).AnyAsync(ct);
        if (!valid) throw new UnauthorizedAccessException("Tenant context is not active.");
    }

    private static double Percent(long numerator,long denominator) => denominator == 0 ? 0 : Math.Round((double)numerator * 100d / denominator,2);
    private static double Percent(int numerator,int denominator) => denominator == 0 ? 0 : Math.Round((double)numerator * 100d / denominator,2);
    private static double ChangePercent(long current,long previous)
    {
        if (previous == 0) return current == 0 ? 0 : 100;
        return Math.Round((double)(current - previous) * 100d / Math.Abs(previous),2);
    }
    private static double ChangePercent(int current,int previous) => ChangePercent((long)current,previous);
    private static string TrendFrom(double revenueChange) => revenueChange >= StableThresholdPercent ? "Growing" : revenueChange <= -StableThresholdPercent ? "Declining" : "Stable";

    private IQueryable<Pos.Domain.Sale> SalesIn(SyncTenantContext tenant,ReportPeriod period) =>
        _db.Sales.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.SaleDateTime >= period.From && x.SaleDateTime < period.ToExclusive);

    private IQueryable<Pos.Domain.Expense> ExpensesIn(SyncTenantContext tenant,ReportPeriod period) =>
        _db.Expenses.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.ExpenseDate >= period.From && x.ExpenseDate < period.ToExclusive);

    public async Task<RemoteSummaryReport> SummaryAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct)
    {
        await EnsureAsync(tenant,ct);
        var sales = SalesIn(tenant,period);
        var grossSales = await sales.Where(x => x.Status == Confirmed || x.Status == Cancelled).SumAsync(x => (long?)x.TotalCents,ct) ?? 0;
        var netSales = await sales.Where(x => x.Status == Confirmed).SumAsync(x => (long?)x.TotalCents,ct) ?? 0;
        var salesCount = await sales.CountAsync(x => x.Status == Confirmed,ct);
        var originalSalesCount = await sales.CountAsync(x => x.Status == Confirmed || x.Status == Cancelled,ct);
        var cancelledCount = await sales.CountAsync(x => x.Status == Cancelled,ct);
        var cancelledCents = await sales.Where(x => x.Status == Cancelled).SumAsync(x => (long?)x.TotalCents,ct) ?? 0;
        var units = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in sales.Where(x => x.Status == Confirmed) on line.SaleId equals sale.Id
            select (int?)line.Quantity).SumAsync(ct) ?? 0;
        var fifoCost = await (
            from allocation in _db.SaleLotAllocations.AsNoTracking()
            join line in _db.SaleLines.AsNoTracking() on allocation.SaleLineId equals line.Id
            join sale in sales.Where(x => x.Status == Confirmed) on line.SaleId equals sale.Id
            select (long?)allocation.TotalCostCents).SumAsync(ct) ?? 0;
        var expenses = await ExpensesIn(tenant,period).SumAsync(x => (long?)x.AmountCents,ct) ?? 0;
        var inventory = await _db.InventoryLots.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.AvailableQuantity > 0)
            .GroupBy(_ => 1)
            .Select(g => new { Units = g.Sum(x => x.AvailableQuantity), Value = g.Sum(x => (long)x.AvailableQuantity * x.UnitCostCents) })
            .SingleOrDefaultAsync(ct);
        var profit = netSales - fifoCost;
        return new RemoteSummaryReport(
            period.From,period.ToExclusive,grossSales,netSales,salesCount,units,
            salesCount == 0 ? 0 : netSales / salesCount,
            fifoCost,profit,Percent(profit,netSales),expenses,profit - expenses,
            cancelledCount,cancelledCents,Percent(cancelledCount,originalSalesCount),
            inventory?.Units ?? 0,inventory?.Value ?? 0);
    }

    private sealed record DailyAggregate(DateTimeOffset Day,long SalesCents,int Transactions,int Units,long CostCents);

    private async Task<IReadOnlyList<DailyAggregate>> DailySalesAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct)
    {
        var sales = SalesIn(tenant,period).Where(x => x.Status == Confirmed);
        var amounts = await sales
            .GroupBy(x => new { x.SaleDateTime.Year,x.SaleDateTime.Month,x.SaleDateTime.Day })
            .Select(g => new { g.Key.Year,g.Key.Month,g.Key.Day,SalesCents = g.Sum(x => x.TotalCents),Transactions = g.Count() })
            .ToListAsync(ct);
        var units = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in sales on line.SaleId equals sale.Id
            group line by new { sale.SaleDateTime.Year,sale.SaleDateTime.Month,sale.SaleDateTime.Day } into g
            select new { g.Key.Year,g.Key.Month,g.Key.Day,Units = g.Sum(x => x.Quantity) }).ToListAsync(ct);
        var costs = await (
            from allocation in _db.SaleLotAllocations.AsNoTracking()
            join line in _db.SaleLines.AsNoTracking() on allocation.SaleLineId equals line.Id
            join sale in sales on line.SaleId equals sale.Id
            group allocation by new { sale.SaleDateTime.Year,sale.SaleDateTime.Month,sale.SaleDateTime.Day } into g
            select new { g.Key.Year,g.Key.Month,g.Key.Day,CostCents = g.Sum(x => x.TotalCostCents) }).ToListAsync(ct);
        var unitMap = units.ToDictionary(x => (x.Year,x.Month,x.Day),x => x.Units);
        var costMap = costs.ToDictionary(x => (x.Year,x.Month,x.Day),x => x.CostCents);
        return amounts.Select(x =>
        {
            var key = (x.Year,x.Month,x.Day);
            var day = new DateTimeOffset(x.Year,x.Month,x.Day,0,0,0,TimeSpan.Zero);
            return new DailyAggregate(day,x.SalesCents,x.Transactions,unitMap.GetValueOrDefault(key),costMap.GetValueOrDefault(key));
        }).OrderBy(x => x.Day).ToList();
    }

    private async Task<IReadOnlyList<DailyAggregate>> DailySalesForUserAsync(SyncTenantContext tenant,ReportPeriod period,Guid userGlobalId,CancellationToken ct)
    {
        var userId = await _db.Users.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.GlobalId == userGlobalId).Select(x => (long?)x.Id).SingleOrDefaultAsync(ct);
        if (userId is null) return [];
        var sales = SalesIn(tenant,period).Where(x => x.Status == Confirmed && x.UserId == userId.Value);
        var amounts = await sales.GroupBy(x => new { x.SaleDateTime.Year,x.SaleDateTime.Month,x.SaleDateTime.Day })
            .Select(g => new { g.Key.Year,g.Key.Month,g.Key.Day,SalesCents = g.Sum(x => x.TotalCents),Transactions = g.Count() }).ToListAsync(ct);
        var units = await (from line in _db.SaleLines.AsNoTracking() join sale in sales on line.SaleId equals sale.Id group line by new { sale.SaleDateTime.Year,sale.SaleDateTime.Month,sale.SaleDateTime.Day } into g select new { g.Key.Year,g.Key.Month,g.Key.Day,Units = g.Sum(x => x.Quantity) }).ToListAsync(ct);
        var costs = await (from allocation in _db.SaleLotAllocations.AsNoTracking() join line in _db.SaleLines.AsNoTracking() on allocation.SaleLineId equals line.Id join sale in sales on line.SaleId equals sale.Id group allocation by new { sale.SaleDateTime.Year,sale.SaleDateTime.Month,sale.SaleDateTime.Day } into g select new { g.Key.Year,g.Key.Month,g.Key.Day,CostCents = g.Sum(x => x.TotalCostCents) }).ToListAsync(ct);
        var unitMap = units.ToDictionary(x => (x.Year,x.Month,x.Day),x => x.Units);
        var costMap = costs.ToDictionary(x => (x.Year,x.Month,x.Day),x => x.CostCents);
        return amounts.Select(x => { var key=(x.Year,x.Month,x.Day); return new DailyAggregate(new DateTimeOffset(x.Year,x.Month,x.Day,0,0,0,TimeSpan.Zero),x.SalesCents,x.Transactions,unitMap.GetValueOrDefault(key),costMap.GetValueOrDefault(key)); }).OrderBy(x => x.Day).ToList();
    }

    public async Task<IReadOnlyList<SalesPeriodRow>> SalesAsync(SyncTenantContext tenant,ReportPeriod period,string groupBy,CancellationToken ct,Guid? userGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var daily = userGlobalId is null
            ? await DailySalesAsync(tenant,period,ct)
            : await DailySalesForUserAsync(tenant,period,userGlobalId.Value,ct);
        groupBy = groupBy.ToLowerInvariant();
        if (groupBy is not ("day" or "week" or "month")) throw new ArgumentException("groupBy must be day, week or month.",nameof(groupBy));
        var buckets = daily.GroupBy(x => BucketStart(x.Day,groupBy)).OrderBy(x => x.Key);
        return buckets.Select(g =>
        {
            var sales = g.Sum(x => x.SalesCents);
            var cost = g.Sum(x => x.CostCents);
            var end = groupBy == "month" ? g.Key.AddMonths(1) : groupBy == "week" ? g.Key.AddDays(7) : g.Key.AddDays(1);
            var label = groupBy == "month" ? g.Key.ToString("yyyy-MM") : groupBy == "week" ? $"{g.Key:yyyy-MM-dd}" : g.Key.ToString("yyyy-MM-dd");
            return new SalesPeriodRow(label,g.Key,end,sales,g.Sum(x => x.Transactions),g.Sum(x => x.Units),cost,sales - cost,Percent(sales - cost,sales));
        }).ToList();
    }

    private static DateTimeOffset BucketStart(DateTimeOffset day,string groupBy)
    {
        if (groupBy == "month") return new DateTimeOffset(day.Year,day.Month,1,0,0,0,TimeSpan.Zero);
        if (groupBy == "week")
        {
            var delta = ((int)day.DayOfWeek + 6) % 7;
            return day.AddDays(-delta);
        }
        return day;
    }

    public async Task<ReportPage<SaleReportDetailRow>> SaleDetailsAsync(SyncTenantContext tenant,ReportPeriod period,int page,int pageSize,CancellationToken ct)
    {
        await EnsureAsync(tenant,ct);
        page = Math.Max(1,page); pageSize = Math.Clamp(pageSize,1,200);
        var query = SalesIn(tenant,period);
        var total = await query.LongCountAsync(ct);
        var items = await query.OrderByDescending(x => x.SaleDateTime).ThenByDescending(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(s => new SaleReportDetailRow(
                s.GlobalId,s.Folio,s.SaleDateTime,
                _db.Users.Where(u => u.BusinessId == tenant.BusinessId && u.Id == s.UserId).Select(u => u.Name).FirstOrDefault() ?? "",
                s.PaymentMethod,s.Status,
                _db.SaleLines.Where(l => l.SaleId == s.Id).Sum(l => (int?)l.Quantity) ?? 0,
                s.TotalCents,
                _db.SaleLotAllocations.Where(a => _db.SaleLines.Where(l => l.SaleId == s.Id).Select(l => l.Id).Contains(a.SaleLineId)).Sum(a => (long?)a.TotalCostCents) ?? 0,
                s.TotalCents - (_db.SaleLotAllocations.Where(a => _db.SaleLines.Where(l => l.SaleId == s.Id).Select(l => l.Id).Contains(a.SaleLineId)).Sum(a => (long?)a.TotalCostCents) ?? 0)))
            .ToListAsync(ct);
        return new ReportPage<SaleReportDetailRow>(page,pageSize,total,items);
    }

    private sealed record ProductSalesAggregate(Guid ProductGlobalId,int Units,long RevenueCents,int Transactions);
    private sealed record ProductCostAggregate(Guid ProductGlobalId,long CostCents);

    private async Task<IReadOnlyList<ProductPerformanceRow>> ProductRowsAsync(SyncTenantContext tenant,ReportPeriod period,Guid? productGlobalId,Guid? categoryGlobalId,CancellationToken ct)
    {
        var confirmed = SalesIn(tenant,period).Where(x => x.Status == Confirmed);
        var productQuery = _db.Products.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (productGlobalId is { } productId) productQuery = productQuery.Where(x => x.GlobalId == productId);
        if (categoryGlobalId is { } categoryId) productQuery = productQuery.Where(x => x.CategoryGlobalId == categoryId);
        var salesAgg = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in confirmed on line.SaleId equals sale.Id
            join product in productQuery on line.ProductGlobalId equals product.GlobalId
            group new { line,sale } by line.ProductGlobalId into g
            select new ProductSalesAggregate(g.Key,g.Sum(x => x.line.Quantity),g.Sum(x => x.line.TotalCents),g.Select(x => x.sale.Id).Distinct().Count())).ToListAsync(ct);
        var costAgg = await (
            from allocation in _db.SaleLotAllocations.AsNoTracking()
            join line in _db.SaleLines.AsNoTracking() on allocation.SaleLineId equals line.Id
            join sale in confirmed on line.SaleId equals sale.Id
            join product in productQuery on line.ProductGlobalId equals product.GlobalId
            group allocation by line.ProductGlobalId into g
            select new ProductCostAggregate(g.Key,g.Sum(x => x.TotalCostCents))).ToListAsync(ct);
        var products = await productQuery.Select(x => new { x.GlobalId,x.Code,x.Name,x.CategoryGlobalId }).ToListAsync(ct);
        var categories = await _db.Categories.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId)
            .ToDictionaryAsync(x => x.GlobalId,x => x.Name,ct);
        var salesMap = salesAgg.ToDictionary(x => x.ProductGlobalId);
        var costMap = costAgg.ToDictionary(x => x.ProductGlobalId,x => x.CostCents);
        return products.Select(p =>
        {
            salesMap.TryGetValue(p.GlobalId,out var s);
            var revenue = s?.RevenueCents ?? 0;
            var cost = costMap.GetValueOrDefault(p.GlobalId);
            var profit = revenue - cost;
            return new ProductPerformanceRow(p.GlobalId,p.Code,p.Name,p.CategoryGlobalId is { } c && categories.TryGetValue(c,out var n) ? n : null,s?.Units ?? 0,revenue,cost,profit,Percent(profit,revenue),s?.Transactions ?? 0);
        }).ToList();
    }

    public async Task<IReadOnlyList<ProductPerformanceRow>> ProductsAsync(SyncTenantContext tenant,ReportPeriod period,string sortBy,bool descending,int top,CancellationToken ct,Guid? productGlobalId=null,Guid? categoryGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        top = Math.Clamp(top,1,200);
        var rows = await ProductRowsAsync(tenant,period,productGlobalId,categoryGlobalId,ct);
        Func<ProductPerformanceRow,IComparable> key = sortBy.ToLowerInvariant() switch
        {
            "units" => x => x.Units,
            "profit" => x => x.GrossProfitCents,
            "margin" => x => x.MarginPercent,
            _ => x => x.RevenueCents
        };
        return (descending ? rows.OrderByDescending(key) : rows.OrderBy(key)).ThenBy(x => x.Name).Take(top).ToList();
    }

    public async Task<IReadOnlyList<ProductPerformanceRow>> LowPerformanceAsync(SyncTenantContext tenant,ReportPeriod period,string metric,int top,CancellationToken ct,Guid? productGlobalId=null,Guid? categoryGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        top = Math.Clamp(top,1,200);
        var rows = await ProductRowsAsync(tenant,period,productGlobalId,categoryGlobalId,ct);
        IEnumerable<ProductPerformanceRow> ordered = metric.ToLowerInvariant() switch
        {
            "no-sales" => rows.Where(x => x.Transactions == 0).OrderBy(x => x.Name),
            "units" => rows.OrderBy(x => x.Units).ThenBy(x => x.RevenueCents),
            "negative-margin" => rows.Where(x => x.GrossProfitCents < 0).OrderBy(x => x.MarginPercent),
            _ => rows.OrderBy(x => x.RevenueCents).ThenBy(x => x.Units)
        };
        return ordered.Take(top).ToList();
    }

    public async Task<IReadOnlyList<CategoryPerformanceRow>> CategoriesAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct,Guid? categoryGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var products = await ProductRowsAsync(tenant,period,null,categoryGlobalId,ct);
        var totalRevenue = products.Sum(x => x.RevenueCents);
        return products.GroupBy(x => x.CategoryName ?? "Sin categoría")
            .Select(g =>
            {
                var revenue = g.Sum(x => x.RevenueCents); var cost = g.Sum(x => x.FifoCostCents); var profit = revenue - cost;
                return new CategoryPerformanceRow(g.Key,g.Sum(x => x.Units),revenue,cost,profit,Percent(profit,revenue),Percent(revenue,totalRevenue));
            }).OrderByDescending(x => x.RevenueCents).ToList();
    }

    public async Task<IReadOnlyList<UserPerformanceRow>> UsersAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct,Guid? userGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var userQuery = _db.Users.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (userGlobalId is { } selectedUser) userQuery = userQuery.Where(x => x.GlobalId == selectedUser);
        var selectedUserIds = userQuery.Select(x => x.Id);
        var sales = SalesIn(tenant,period).Where(x => selectedUserIds.Contains(x.UserId));
        var confirmed = await sales.Where(x => x.Status == Confirmed).GroupBy(x => x.UserId)
            .Select(g => new { UserId = g.Key,Sales = g.Count(),Revenue = g.Sum(x => x.TotalCents) }).ToListAsync(ct);
        var units = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in sales.Where(x => x.Status == Confirmed) on line.SaleId equals sale.Id
            group line by sale.UserId into g
            select new { UserId = g.Key,Units = g.Sum(x => x.Quantity) }).ToListAsync(ct);
        var cancelled = await sales.Where(x => x.Status == Cancelled).GroupBy(x => x.UserId)
            .Select(g => new { UserId = g.Key,Sales = g.Count(),Amount = g.Sum(x => x.TotalCents) }).ToListAsync(ct);
        var users = await userQuery.Select(x => new { x.Id,x.GlobalId,x.Name,x.Role }).ToListAsync(ct);
        var saleMap = confirmed.ToDictionary(x => x.UserId); var unitMap = units.ToDictionary(x => x.UserId,x => x.Units); var cancelMap = cancelled.ToDictionary(x => x.UserId);
        return users.Select(u =>
        {
            saleMap.TryGetValue(u.Id,out var s); cancelMap.TryGetValue(u.Id,out var c);
            var count = s?.Sales ?? 0; var revenue = s?.Revenue ?? 0;
            return new UserPerformanceRow(u.GlobalId,u.Name,u.Role,count,unitMap.GetValueOrDefault(u.Id),revenue,count == 0 ? 0 : revenue / count,c?.Sales ?? 0,c?.Amount ?? 0);
        }).OrderByDescending(x => x.RevenueCents).ToList();
    }

    public async Task<IReadOnlyList<PurchaseReportRow>> PurchasesAsync(SyncTenantContext tenant,ReportPeriod period,string groupBy,CancellationToken ct,Guid? supplierGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var purchases = _db.Purchases.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.PurchaseDate >= period.From && x.PurchaseDate < period.ToExclusive && x.Status == Confirmed);
        if (supplierGlobalId is { } selectedSupplier) purchases = purchases.Where(x => x.SupplierGlobalId == selectedSupplier);
        groupBy = groupBy.ToLowerInvariant();
        if (groupBy == "product")
        {
            var rows = await (
                from line in _db.PurchaseLines.AsNoTracking()
                join purchase in purchases on line.PurchaseId equals purchase.Id
                group new { line,purchase } by line.ProductGlobalId into g
                select new { ProductGlobalId = g.Key,Purchases = g.Select(x => x.purchase.Id).Distinct().Count(),Units = g.Sum(x => x.line.Quantity),Amount = g.Sum(x => x.line.SubtotalCents) }).ToListAsync(ct);
            var names = await _db.Products.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId).ToDictionaryAsync(x => x.GlobalId,x => x.Name,ct);
            return rows.Select(x => new PurchaseReportRow(x.ProductGlobalId.ToString(),names.GetValueOrDefault(x.ProductGlobalId,x.ProductGlobalId.ToString()),x.Purchases,x.Units,x.Amount,x.Units == 0 ? 0 : x.Amount / x.Units)).OrderByDescending(x => x.AmountCents).ToList();
        }
        if (groupBy == "supplier")
        {
            var amounts = await purchases.GroupBy(x => x.SupplierGlobalId).Select(g => new { SupplierGlobalId = g.Key,Purchases = g.Count(),Amount = g.Sum(x => x.TotalCents) }).ToListAsync(ct);
            var units = await (from line in _db.PurchaseLines.AsNoTracking() join purchase in purchases on line.PurchaseId equals purchase.Id group line by purchase.SupplierGlobalId into g select new { SupplierGlobalId = g.Key,Units = g.Sum(x => x.Quantity) }).ToListAsync(ct);
            var suppliers = await _db.Suppliers.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId).ToDictionaryAsync(x => x.GlobalId,x => x.Name,ct);
            var unitMap = units.ToDictionary(x => x.SupplierGlobalId,x => x.Units);
            return amounts.Select(x => { var q = unitMap.GetValueOrDefault(x.SupplierGlobalId); return new PurchaseReportRow(x.SupplierGlobalId.ToString(),suppliers.GetValueOrDefault(x.SupplierGlobalId,x.SupplierGlobalId.ToString()),x.Purchases,q,x.Amount,q == 0 ? 0 : x.Amount / q); }).OrderByDescending(x => x.AmountCents).ToList();
        }
        if (groupBy is not ("day" or "month")) throw new ArgumentException("groupBy must be supplier, product, day or month.",nameof(groupBy));
        var dailyAmounts = await purchases.GroupBy(x => new { x.PurchaseDate.Year,x.PurchaseDate.Month,x.PurchaseDate.Day }).Select(g => new { g.Key.Year,g.Key.Month,g.Key.Day,Purchases = g.Count(),Amount = g.Sum(x => x.TotalCents) }).ToListAsync(ct);
        var dailyUnits = await (from line in _db.PurchaseLines.AsNoTracking() join purchase in purchases on line.PurchaseId equals purchase.Id group line by new { purchase.PurchaseDate.Year,purchase.PurchaseDate.Month,purchase.PurchaseDate.Day } into g select new { g.Key.Year,g.Key.Month,g.Key.Day,Units = g.Sum(x => x.Quantity) }).ToListAsync(ct);
        var unitByDay = dailyUnits.ToDictionary(x => (x.Year,x.Month,x.Day),x => x.Units);
        var daily = dailyAmounts.Select(x => new { Day = new DateTimeOffset(x.Year,x.Month,x.Day,0,0,0,TimeSpan.Zero),x.Purchases,x.Amount,Units = unitByDay.GetValueOrDefault((x.Year,x.Month,x.Day)) });
        return daily.GroupBy(x => groupBy == "month" ? new DateTimeOffset(x.Day.Year,x.Day.Month,1,0,0,0,TimeSpan.Zero) : x.Day)
            .Select(g => { var unitsTotal = g.Sum(x => x.Units); var amount = g.Sum(x => x.Amount); return new PurchaseReportRow(g.Key.ToString(groupBy == "month" ? "yyyy-MM" : "yyyy-MM-dd"),g.Key.ToString(groupBy == "month" ? "yyyy-MM" : "yyyy-MM-dd"),g.Sum(x => x.Purchases),unitsTotal,amount,unitsTotal == 0 ? 0 : amount / unitsTotal); })
            .OrderBy(x => x.GroupKey).ToList();
    }

    public async Task<IReadOnlyList<SupplierPerformanceRow>> SuppliersAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct,Guid? supplierGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var purchases = _db.Purchases.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.PurchaseDate >= period.From && x.PurchaseDate < period.ToExclusive && x.Status == Confirmed);
        if (supplierGlobalId is { } selectedSupplier) purchases = purchases.Where(x => x.SupplierGlobalId == selectedSupplier);
        var purchaseAgg = await purchases.GroupBy(x => x.SupplierGlobalId).Select(g => new { SupplierGlobalId = g.Key,Purchases = g.Count(),Amount = g.Sum(x => x.TotalCents),Last = g.Max(x => x.PurchaseDate) }).ToListAsync(ct);
        var lineAgg = await (from line in _db.PurchaseLines.AsNoTracking() join purchase in purchases on line.PurchaseId equals purchase.Id group new { line,purchase } by purchase.SupplierGlobalId into g select new { SupplierGlobalId = g.Key,Units = g.Sum(x => x.line.Quantity),Products = g.Select(x => x.line.ProductGlobalId).Distinct().Count() }).ToListAsync(ct);
        var supplierQuery = _db.Suppliers.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (supplierGlobalId is { } selectedSupplierForList) supplierQuery = supplierQuery.Where(x => x.GlobalId == selectedSupplierForList);
        var suppliers = await supplierQuery.Select(x => new { x.GlobalId,x.Name }).ToListAsync(ct);
        var pMap = purchaseAgg.ToDictionary(x => x.SupplierGlobalId); var lMap = lineAgg.ToDictionary(x => x.SupplierGlobalId);
        return suppliers.Select(s => { pMap.TryGetValue(s.GlobalId,out var p); lMap.TryGetValue(s.GlobalId,out var l); return new SupplierPerformanceRow(s.GlobalId,s.Name,p?.Purchases ?? 0,l?.Units ?? 0,p?.Amount ?? 0,l?.Products ?? 0,p?.Last); }).OrderByDescending(x => x.AmountCents).ToList();
    }

    public async Task<IReadOnlyList<InventoryReportRow>> InventoryAsync(SyncTenantContext tenant,CancellationToken ct,Guid? productGlobalId=null,Guid? categoryGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        var productQuery = _db.Products.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (productGlobalId is { } productId) productQuery = productQuery.Where(x => x.GlobalId == productId);
        if (categoryGlobalId is { } categoryId) productQuery = productQuery.Where(x => x.CategoryGlobalId == categoryId);
        var selectedProducts = productQuery.Select(x => x.GlobalId);
        var lots = await _db.InventoryLots.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && selectedProducts.Contains(x.ProductGlobalId))
            .GroupBy(x => x.ProductGlobalId)
            .Select(g => new { ProductGlobalId = g.Key,Stock = g.Sum(x => x.AvailableQuantity),ActiveLots = g.Count(x => x.Active && x.AvailableQuantity > 0),Value = g.Sum(x => (long)x.AvailableQuantity * x.UnitCostCents),LastEntry = g.Max(x => (DateTimeOffset?)x.EntryDate) }).ToListAsync(ct);
        var lastSales = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in _db.Sales.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.Status == Confirmed) on line.SaleId equals sale.Id
            where selectedProducts.Contains(line.ProductGlobalId)
            group sale by line.ProductGlobalId into g
            select new { ProductGlobalId = g.Key,LastSale = g.Max(x => (DateTimeOffset?)x.SaleDateTime) }).ToListAsync(ct);
        var products = await productQuery.Select(x => new { x.GlobalId,x.Code,x.Name,x.MinimumStock }).ToListAsync(ct);
        var lotMap = lots.ToDictionary(x => x.ProductGlobalId); var saleMap = lastSales.ToDictionary(x => x.ProductGlobalId,x => x.LastSale);
        return products.Select(p => { lotMap.TryGetValue(p.GlobalId,out var l); var stock = l?.Stock ?? 0; var value = l?.Value ?? 0; return new InventoryReportRow(p.GlobalId,p.Code,p.Name,stock,p.MinimumStock,l?.ActiveLots ?? 0,value,stock == 0 ? 0 : value / stock,l?.LastEntry,saleMap.GetValueOrDefault(p.GlobalId)); }).OrderBy(x => x.Name).ToList();
    }

    public async Task<ExpenseReportResponse> ExpensesAsync(SyncTenantContext tenant,ReportPeriod period,string groupBy,int page,int pageSize,CancellationToken ct,Guid? userGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        page = Math.Max(1,page); pageSize = Math.Clamp(pageSize,1,200);
        var expenses = ExpensesIn(tenant,period);
        if (userGlobalId is { } selectedUser)
        {
            var userIds = _db.Users.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.GlobalId == selectedUser).Select(x => x.Id);
            expenses = expenses.Where(x => userIds.Contains(x.UserId));
        }
        var total = await expenses.SumAsync(x => (long?)x.AmountCents,ct) ?? 0; var count = await expenses.CountAsync(ct);
        IReadOnlyList<ExpenseBreakdownRow> breakdown;
        if (groupBy == "category")
        {
            var grouped = await expenses
                .GroupBy(x => x.Category)
                .Select(g => new
                {
                    Category = g.Key,
                    AmountCents = g.Sum(x => x.AmountCents),
                    Count = g.Count()
                })
                .OrderByDescending(x => x.AmountCents)
                .ToListAsync(ct);

            breakdown = grouped
                .Select(x => new ExpenseBreakdownRow(
                    x.Category ?? "Sin categoría",
                    x.AmountCents,
                    x.Count))
                .ToList();
        }
        else
        {
            var daily = await expenses.GroupBy(x => new { x.ExpenseDate.Year,x.ExpenseDate.Month,x.ExpenseDate.Day }).Select(g => new { g.Key.Year,g.Key.Month,g.Key.Day,Amount = g.Sum(x => x.AmountCents),Count = g.Count() }).ToListAsync(ct);
            if (groupBy is not ("day" or "month")) throw new ArgumentException("groupBy must be category, day or month.",nameof(groupBy));
            breakdown = daily.GroupBy(x => groupBy == "month" ? $"{x.Year:D4}-{x.Month:D2}" : $"{x.Year:D4}-{x.Month:D2}-{x.Day:D2}").Select(g => new ExpenseBreakdownRow(g.Key,g.Sum(x => x.Amount),g.Sum(x => x.Count))).OrderBy(x => x.Group).ToList();
        }
        var details = await expenses.OrderByDescending(x => x.ExpenseDate).ThenByDescending(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new ExpenseDetailRow(x.GlobalId,x.ExpenseDate,x.Concept,x.Category,x.PaymentMethod,_db.Users.Where(u => u.BusinessId == tenant.BusinessId && u.Id == x.UserId).Select(u => u.Name).FirstOrDefault() ?? "",x.AmountCents)).ToListAsync(ct);
        return new ExpenseReportResponse(total,count,breakdown,new ReportPage<ExpenseDetailRow>(page,pageSize,count,details));
    }

    public async Task<ReportPage<CashReportRow>> CashAsync(SyncTenantContext tenant,ReportPeriod period,int page,int pageSize,CancellationToken ct,Guid? userGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        page = Math.Max(1,page); pageSize = Math.Clamp(pageSize,1,200);
        var sessions = _db.CashSessions.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.OpenedAt < period.ToExclusive && (x.ClosedAt == null || x.ClosedAt >= period.From));
        if (userGlobalId is { } selectedUser)
        {
            var userIds = _db.Users.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.GlobalId == selectedUser).Select(x => x.Id);
            sessions = sessions.Where(x => userIds.Contains(x.UserId));
        }
        var total = await sessions.LongCountAsync(ct);
        var items = await sessions.OrderByDescending(x => x.OpenedAt).ThenByDescending(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(c => new CashReportRow(
                c.GlobalId,
                _db.Users.Where(u => u.BusinessId == tenant.BusinessId && u.Id == c.UserId).Select(u => u.Name).FirstOrDefault() ?? "",
                c.OpenedAt,c.ClosedAt,c.Status,c.OpeningBalanceCents,
                _db.Sales.Where(s => s.BusinessId == tenant.BusinessId && s.BranchId == c.BranchId && s.DeviceId == c.DeviceId && s.Status == Confirmed && s.PaymentMethod == "Cash" && s.SaleDateTime >= c.OpenedAt && s.SaleDateTime < (c.ClosedAt ?? period.ToExclusive)).Sum(s => (long?)s.TotalCents) ?? 0,
                _db.Expenses.Where(e => e.BusinessId == tenant.BusinessId && e.BranchId == c.BranchId && e.DeviceId == c.DeviceId && e.PaymentMethod == "Cash" && e.ExpenseDate >= c.OpenedAt && e.ExpenseDate < (c.ClosedAt ?? period.ToExclusive)).Sum(e => (long?)e.AmountCents) ?? 0,
                c.OpeningBalanceCents
                    + (_db.Sales.Where(s => s.BusinessId == tenant.BusinessId && s.BranchId == c.BranchId && s.DeviceId == c.DeviceId && s.Status == Confirmed && s.PaymentMethod == "Cash" && s.SaleDateTime >= c.OpenedAt && s.SaleDateTime < (c.ClosedAt ?? period.ToExclusive)).Sum(s => (long?)s.TotalCents) ?? 0)
                    - (_db.Expenses.Where(e => e.BusinessId == tenant.BusinessId && e.BranchId == c.BranchId && e.DeviceId == c.DeviceId && e.PaymentMethod == "Cash" && e.ExpenseDate >= c.OpenedAt && e.ExpenseDate < (c.ClosedAt ?? period.ToExclusive)).Sum(e => (long?)e.AmountCents) ?? 0),
                c.ExpectedCashCents,c.CountedCashCents,c.DifferenceCents)).ToListAsync(ct);
        return new ReportPage<CashReportRow>(page,pageSize,total,items);
    }

    public async Task<IReadOnlyList<PaymentMethodReportRow>> PaymentMethodsAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct)
    {
        await EnsureAsync(tenant,ct);
        var rows = await SalesIn(tenant,period).Where(x => x.Status == Confirmed).GroupBy(x => x.PaymentMethod)
            .Select(g => new { PaymentMethod = g.Key,Transactions = g.Count(),Amount = g.Sum(x => x.TotalCents) }).ToListAsync(ct);
        var total = rows.Sum(x => x.Amount);
        return rows.Select(x => new PaymentMethodReportRow(x.PaymentMethod,x.Transactions,x.Amount,Percent(x.Amount,total))).OrderByDescending(x => x.AmountCents).ToList();
    }

    public async Task<CancellationReportResponse> CancellationsAsync(SyncTenantContext tenant,ReportPeriod period,int page,int pageSize,CancellationToken ct,Guid? userGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        page = Math.Max(1,page); pageSize = Math.Clamp(pageSize,1,200);
        var sales = SalesIn(tenant,period);
        if (userGlobalId is { } selectedUser)
        {
            var userIds = _db.Users.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId && x.GlobalId == selectedUser).Select(x => x.Id);
            sales = sales.Where(x => userIds.Contains(x.UserId));
        }
        var originals = sales.Where(x => x.Status == Confirmed || x.Status == Cancelled);
        var cancelled = sales.Where(x => x.Status == Cancelled);
        var originalCount = await originals.CountAsync(ct); var originalCents = await originals.SumAsync(x => (long?)x.TotalCents,ct) ?? 0;
        var cancelledCount = await cancelled.CountAsync(ct); var cancelledCents = await cancelled.SumAsync(x => (long?)x.TotalCents,ct) ?? 0;
        var cancelledUnits = await (from line in _db.SaleLines.AsNoTracking() join sale in cancelled on line.SaleId equals sale.Id select (int?)line.Quantity).SumAsync(ct) ?? 0;
        var details = await cancelled.OrderByDescending(x => x.CancelledAt).ThenByDescending(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(s => new CancellationReportRow(s.GlobalId,s.Folio,s.SaleDateTime,s.CancelledAt,_db.Users.Where(u => u.BusinessId == tenant.BusinessId && u.Id == s.UserId).Select(u => u.Name).FirstOrDefault() ?? "",s.CancellationReason,_db.SaleLines.Where(l => l.SaleId == s.Id).Sum(l => (int?)l.Quantity) ?? 0,s.TotalCents)).ToListAsync(ct);
        return new CancellationReportResponse(originalCount,originalCents,cancelledCount,cancelledCents,cancelledUnits,Percent(cancelledCount,originalCount),new ReportPage<CancellationReportRow>(page,pageSize,cancelledCount,details));
    }

    private sealed record ProductTrendAggregate(Guid ProductGlobalId,int Units,long RevenueCents);
    private async Task<IReadOnlyList<ProductTrendAggregate>> ProductTrendAggregateAsync(SyncTenantContext tenant,ReportPeriod period,CancellationToken ct,Guid? productGlobalId=null,Guid? categoryGlobalId=null)
    {
        var products = _db.Products.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (productGlobalId is { } productId) products = products.Where(x => x.GlobalId == productId);
        if (categoryGlobalId is { } categoryId) products = products.Where(x => x.CategoryGlobalId == categoryId);
        return await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in SalesIn(tenant,period).Where(x => x.Status == Confirmed) on line.SaleId equals sale.Id
            join product in products on line.ProductGlobalId equals product.GlobalId
            group line by line.ProductGlobalId into g
            select new ProductTrendAggregate(g.Key,g.Sum(x => x.Quantity),g.Sum(x => x.TotalCents))).ToListAsync(ct);
    }

    public async Task<IReadOnlyList<ProductTrendRow>> ProductTrendsAsync(SyncTenantContext tenant,ReportPeriod current,int top,CancellationToken ct,Guid? productGlobalId=null,Guid? categoryGlobalId=null)
    {
        await EnsureAsync(tenant,ct);
        top = Math.Clamp(top,1,200);
        var duration = current.ToExclusive - current.From;
        var previous = new ReportPeriod(current.From - duration,current.From);
        var currentAgg = await ProductTrendAggregateAsync(tenant,current,ct,productGlobalId,categoryGlobalId);
        var previousAgg = await ProductTrendAggregateAsync(tenant,previous,ct,productGlobalId,categoryGlobalId);
        var productQuery = _db.Products.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId);
        if (productGlobalId is { } productId) productQuery = productQuery.Where(x => x.GlobalId == productId);
        if (categoryGlobalId is { } categoryId) productQuery = productQuery.Where(x => x.CategoryGlobalId == categoryId);
        var products = await productQuery.Select(x => new { x.GlobalId,x.Code,x.Name }).ToListAsync(ct);
        var currentMap = currentAgg.ToDictionary(x => x.ProductGlobalId); var previousMap = previousAgg.ToDictionary(x => x.ProductGlobalId);
        return products.Select(p =>
        {
            currentMap.TryGetValue(p.GlobalId,out var c); previousMap.TryGetValue(p.GlobalId,out var old);
            var currentUnits = c?.Units ?? 0; var previousUnits = old?.Units ?? 0; var currentRevenue = c?.RevenueCents ?? 0; var previousRevenue = old?.RevenueCents ?? 0;
            var revenueChange = ChangePercent(currentRevenue,previousRevenue);
            return new ProductTrendRow(p.GlobalId,p.Code,p.Name,currentUnits,previousUnits,currentRevenue,previousRevenue,ChangePercent(currentUnits,previousUnits),revenueChange,TrendFrom(revenueChange));
        }).Where(x => x.CurrentRevenueCents != 0 || x.PreviousRevenueCents != 0).OrderBy(x => x.RevenueChangePercent).Take(top).ToList();
    }
}
