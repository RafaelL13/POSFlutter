using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class PosAdminInsightsServiceTests
{
    private static SyncTenantContext Context(
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant) =>
        new(
            tenant.Business.Id,
            tenant.Business.GlobalId,
            tenant.Branch.Id,
            tenant.Branch.GlobalId,
            tenant.Device.Id,
            tenant.Device.GlobalId,
            tenant.User.Id,
            tenant.User.GlobalId,
            tenant.User.Role,
            tenant.Device.Mode);

    [Fact]
    public async Task Sync_status_is_business_scoped_and_classifies_freshness()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("POSADMIN");
        var foreign = await test.SeedTenantAsync("FOREIGN");
        var now = DateTimeOffset.UtcNow;

        tenant.Device.LastSyncAt = now.AddMinutes(-1);
        foreign.Device.LastSyncAt = now;

        test.Db.Devices.AddRange(
            new Device
            {
                GlobalId = Guid.NewGuid(),
                BranchId = tenant.Branch.Id,
                Name = "Delayed",
                Mode = "PointOfSale",
                Active = true,
                CreatedAt = now,
                LastSyncAt = now.AddMinutes(-10)
            },
            new Device
            {
                GlobalId = Guid.NewGuid(),
                BranchId = tenant.Branch.Id,
                Name = "Stale",
                Mode = "PointOfSale",
                Active = true,
                CreatedAt = now,
                LastSyncAt = now.AddHours(-2)
            },
            new Device
            {
                GlobalId = Guid.NewGuid(),
                BranchId = tenant.Branch.Id,
                Name = "Never",
                Mode = "PointOfSale",
                Active = true,
                CreatedAt = now,
                LastSyncAt = null
            });
        await test.Db.SaveChangesAsync();

        var result = await new PosAdminInsightsService(test.Db)
            .SyncStatusAsync(Context(tenant), CancellationToken.None);

        Assert.Equal(4, result.TotalDevices);
        Assert.Equal(1, result.CurrentDevices);
        Assert.Equal(1, result.DelayedDevices);
        Assert.Equal(1, result.StaleDevices);
        Assert.Equal(1, result.NeverSyncedDevices);
        Assert.DoesNotContain(
            result.Devices,
            x => x.DeviceGlobalId == foreign.Device.GlobalId);
    }

    [Fact]
    public async Task Branch_report_uses_fifo_allocations_and_is_business_scoped()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("BRANCHES");
        var foreign = await test.SeedTenantAsync("FOREIGN-BRANCH");
        var now = DateTimeOffset.UtcNow;

        var branch2 = new Branch
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Name = "Sucursal 2",
            Active = true,
            CreatedAt = now,
            UpdatedAt = now
        };
        test.Db.Branches.Add(branch2);
        await test.Db.SaveChangesAsync();

        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "P1",
            Name = "Producto",
            SalePriceCents = 1000,
            UpdatedAt = now
        };
        test.Db.Products.Add(product);
        await test.Db.SaveChangesAsync();

        async Task AddSale(long branchId, long totalCents, long persistedCost, long allocationCost)
        {
            var sale = new Sale
            {
                GlobalId = Guid.NewGuid(),
                IdempotencyKey = Guid.NewGuid(),
                BusinessId = tenant.Business.Id,
                BranchId = branchId,
                DeviceId = tenant.Device.Id,
                UserId = tenant.User.Id,
                Folio = Guid.NewGuid().ToString("N")[..8],
                SaleDateTime = now,
                SubtotalCents = totalCents,
                TotalCents = totalCents,
                FifoCostCents = persistedCost,
                GrossProfitCents = totalCents - persistedCost,
                PaymentMethod = "Cash",
                Status = "Confirmed",
                CreatedAt = now
            };
            test.Db.Sales.Add(sale);
            await test.Db.SaveChangesAsync();

            var line = new SaleLine
            {
                GlobalId = Guid.NewGuid(),
                SaleId = sale.Id,
                ProductGlobalId = product.GlobalId,
                Quantity = 1,
                UnitPriceCents = totalCents,
                TotalCents = totalCents,
                FifoCostCents = persistedCost
            };
            test.Db.SaleLines.Add(line);
            await test.Db.SaveChangesAsync();

            test.Db.SaleLotAllocations.Add(
                new SaleLotAllocation
                {
                    GlobalId = Guid.NewGuid(),
                    SaleLineId = line.Id,
                    InventoryLotGlobalId = Guid.NewGuid(),
                    Quantity = 1,
                    UnitCostCents = allocationCost,
                    TotalCostCents = allocationCost
                });
            await test.Db.SaveChangesAsync();
        }

        await AddSale(tenant.Branch.Id, 1000, 9999, 200);
        await AddSale(branch2.Id, 2000, 8888, 700);

        var foreignProduct = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = foreign.Business.Id,
            Code = "F1",
            Name = "Foreign",
            SalePriceCents = 9999,
            UpdatedAt = now
        };
        test.Db.Products.Add(foreignProduct);
        await test.Db.SaveChangesAsync();

        var result = await new PosAdminInsightsService(test.Db)
            .BranchesAsync(
                Context(tenant),
                new ReportPeriod(now.AddDays(-1), now.AddDays(1)),
                CancellationToken.None);

        Assert.Equal(2, result.Count);
        var main = Assert.Single(result.Where(x => x.BranchGlobalId == tenant.Branch.GlobalId));
        var second = Assert.Single(result.Where(x => x.BranchGlobalId == branch2.GlobalId));

        Assert.Equal(1000, main.NetSalesCents);
        Assert.Equal(200, main.FifoCostCents);
        Assert.Equal(800, main.GrossProfitCents);
        Assert.Equal(2000, second.NetSalesCents);
        Assert.Equal(700, second.FifoCostCents);
        Assert.Equal(1300, second.GrossProfitCents);
        Assert.DoesNotContain(result, x => x.BranchGlobalId == foreign.Branch.GlobalId);
    }
}
