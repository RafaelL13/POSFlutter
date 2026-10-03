using Microsoft.EntityFrameworkCore;
using Pos.Application;

namespace Pos.Infrastructure;

public sealed class PosAdminInsightsService(PosDbContext db)
{
    private const string Confirmed = "Confirmed";
    private const string Cancelled = "Cancelled";
    private readonly PosDbContext _db = db;

    private static double Percent(long numerator, long denominator) =>
        denominator == 0
            ? 0
            : Math.Round((double)numerator * 100d / denominator, 2);

    private async Task EnsureActiveTenantAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var valid = await (
            from business in _db.Businesses.AsNoTracking()
            join branch in _db.Branches.AsNoTracking()
                on business.Id equals branch.BusinessId
            join device in _db.Devices.AsNoTracking()
                on branch.Id equals device.BranchId
            join user in _db.Users.AsNoTracking()
                on business.Id equals user.BusinessId
            where business.Id == tenant.BusinessId
                && business.GlobalId == tenant.BusinessGlobalId
                && business.Active
                && branch.Id == tenant.BranchId
                && branch.GlobalId == tenant.BranchGlobalId
                && branch.Active
                && device.Id == tenant.DeviceId
                && device.GlobalId == tenant.DeviceGlobalId
                && device.Active
                && device.Mode == tenant.DeviceMode
                && user.Id == tenant.UserId
                && user.GlobalId == tenant.UserGlobalId
                && user.Active
                && user.Role == tenant.Role
            select business.Id)
            .AnyAsync(cancellationToken);

        if (!valid)
        {
            throw new UnauthorizedAccessException(
                "Tenant context is not active.");
        }
    }

    public async Task<PosAdminSyncOverview> SyncStatusAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        BackendReadAuthorization.Require(
            tenant,
            BackendReadCapability.DevicesRead);
        await EnsureActiveTenantAsync(tenant, cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var rows = await (
            from device in _db.Devices.AsNoTracking()
            join branch in _db.Branches.AsNoTracking()
                on device.BranchId equals branch.Id
            where branch.BusinessId == tenant.BusinessId
            orderby branch.Name, device.Name
            select new
            {
                DeviceGlobalId = device.GlobalId,
                BranchGlobalId = branch.GlobalId,
                BranchName = branch.Name,
                DeviceName = device.Name,
                device.Mode,
                device.Active,
                device.LastSyncAt
            }).ToListAsync(cancellationToken);

        var devices = rows.Select(row =>
        {
            int? ageMinutes = row.LastSyncAt is null
                ? null
                : Math.Max(
                    0,
                    (int)Math.Floor(
                        (now - row.LastSyncAt.Value).TotalMinutes));

            var freshness = !row.Active
                ? "Inactive"
                : ageMinutes is null
                    ? "Never"
                    : ageMinutes <= 2
                        ? "Current"
                        : ageMinutes <= 30
                            ? "Delayed"
                            : "Stale";

            return new PosAdminDeviceSyncRow(
                row.DeviceGlobalId,
                row.BranchGlobalId,
                row.BranchName,
                row.DeviceName,
                row.Mode,
                row.Active,
                row.LastSyncAt,
                ageMinutes,
                freshness);
        }).ToList();

        return new PosAdminSyncOverview(
            now,
            devices.Count,
            devices.Count(x => x.Freshness == "Current"),
            devices.Count(x => x.Freshness == "Delayed"),
            devices.Count(x => x.Freshness == "Stale"),
            devices.Count(x => x.Freshness == "Never"),
            devices);
    }

    public async Task<IReadOnlyList<BranchPerformanceRow>> BranchesAsync(
        SyncTenantContext tenant,
        ReportPeriod period,
        CancellationToken cancellationToken)
    {
        BackendReadAuthorization.Require(
            tenant,
            BackendReadCapability.FinancialReportsRead);
        await EnsureActiveTenantAsync(tenant, cancellationToken);

        var sales = _db.Sales.AsNoTracking().Where(
            sale =>
                sale.BusinessId == tenant.BusinessId &&
                sale.SaleDateTime >= period.From &&
                sale.SaleDateTime < period.ToExclusive);

        var aggregates = await sales
            .GroupBy(sale => sale.BranchId)
            .Select(group => new
            {
                BranchId = group.Key,
                SalesCount = group.Count(x => x.Status == Confirmed),
                NetSalesCents = group
                    .Where(x => x.Status == Confirmed)
                    .Sum(x => (long?)x.TotalCents) ?? 0,
                CancelledSalesCount = group.Count(x => x.Status == Cancelled),
                CancelledSalesCents = group
                    .Where(x => x.Status == Cancelled)
                    .Sum(x => (long?)x.TotalCents) ?? 0
            })
            .ToListAsync(cancellationToken);

        var confirmedSales = sales.Where(x => x.Status == Confirmed);

        var units = await (
            from line in _db.SaleLines.AsNoTracking()
            join sale in confirmedSales
                on line.SaleId equals sale.Id
            group line by sale.BranchId
            into group
            select new
            {
                BranchId = group.Key,
                Units = group.Sum(x => x.Quantity)
            }).ToListAsync(cancellationToken);

        var costs = await (
            from allocation in _db.SaleLotAllocations.AsNoTracking()
            join line in _db.SaleLines.AsNoTracking()
                on allocation.SaleLineId equals line.Id
            join sale in confirmedSales
                on line.SaleId equals sale.Id
            group allocation by sale.BranchId
            into group
            select new
            {
                BranchId = group.Key,
                CostCents = group.Sum(x => x.TotalCostCents)
            }).ToListAsync(cancellationToken);

        var branches = await _db.Branches.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.Active)
            .Select(x => new { x.Id, x.GlobalId, x.Name })
            .ToListAsync(cancellationToken);

        var aggregateMap = aggregates.ToDictionary(x => x.BranchId);
        var unitMap = units.ToDictionary(x => x.BranchId, x => x.Units);
        var costMap = costs.ToDictionary(x => x.BranchId, x => x.CostCents);

        return branches
            .Select(branch =>
            {
                aggregateMap.TryGetValue(branch.Id, out var aggregate);
                var revenue = aggregate?.NetSalesCents ?? 0;
                var cost = costMap.GetValueOrDefault(branch.Id);
                var profit = revenue - cost;
                return new BranchPerformanceRow(
                    branch.GlobalId,
                    branch.Name,
                    aggregate?.SalesCount ?? 0,
                    unitMap.GetValueOrDefault(branch.Id),
                    revenue,
                    cost,
                    profit,
                    Percent(profit, revenue),
                    aggregate?.CancelledSalesCount ?? 0,
                    aggregate?.CancelledSalesCents ?? 0);
            })
            .OrderByDescending(x => x.NetSalesCents)
            .ThenBy(x => x.BranchName)
            .ToList();
    }
}
