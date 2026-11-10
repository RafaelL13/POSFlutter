using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

/// <summary>Real SQL Server checkout gate. Uses temporary, randomly named lab DBs only.</summary>
public sealed class WebCheckoutSqlTests
{
    [Fact]
    public async Task Sale_mixed_payment_consumes_fifo_and_retry_does_not_duplicate()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB1");
        var (product, oldLot, newLot) = await SeedLotsAsync(test, tenant);
        var ctx = Context(tenant);
        var key = Guid.NewGuid();
        var request = new WebCheckoutRequest(key,
            [new WebCheckoutLine(product.GlobalId, 3)],
            [new WebCheckoutPayment("Cash", 100), new WebCheckoutPayment("Card", 200)], 120);
        var service = new WebCheckoutService(test.Db);
        var first = await service.CheckoutAsync(request, ctx, TestContext.Current.CancellationToken);
        Assert.False(first.AlreadyProcessed);
        Assert.Equal(300, first.TotalCents);
        Assert.Equal(50, first.FifoCostCents); // two at 10, one at 30
        var second = await service.CheckoutAsync(request, ctx, TestContext.Current.CancellationToken);
        Assert.True(second.AlreadyProcessed);
        Assert.Equal(first.SaleGlobalId, second.SaleGlobalId);
        test.Db.ChangeTracker.Clear();
        Assert.Single(await test.Db.Sales.ToListAsync());
        var sale = await test.Db.Sales.Include(x => x.Payments).Include(x => x.Lines)
            .ThenInclude(x => x.Lots).SingleAsync();
        Assert.Equal(2, sale.Payments.Count);
        Assert.Equal(tenant.Device.Id, (await test.Db.CashSessions.SingleAsync()).DeviceId);
        Assert.Equal((await test.Db.CashSessions.SingleAsync()).Id, sale.Payments.Single(x => x.Method == "Cash").CashSessionId);
        Assert.Equal(20, sale.ChangeCents);
        Assert.Equal(2, sale.Lines.Single().Lots.Count);
        Assert.Equal(0, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == oldLot.GlobalId)).AvailableQuantity);
        Assert.Equal(3, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == newLot.GlobalId)).AvailableQuantity);
        Assert.Single(await test.Db.InventoryMovements.Where(x => x.ReferenceGlobalId == first.SaleGlobalId).ToListAsync());
        var change = await test.Db.SyncChanges.SingleAsync(x => x.EntityGlobalId == first.SaleGlobalId);
        Assert.Equal(WebSaleInventoryV1.EntityType, change.EntityType);
        Assert.Equal(WebSaleInventoryV1.Version, change.Version);
        Assert.Contains(oldLot.GlobalId.ToString(), change.PayloadJson, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(newLot.GlobalId.ToString(), change.PayloadJson, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Different_tender_with_same_key_is_rejected_without_new_sale()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB2");
        var (product, oldLot, newLot) = await SeedLotsAsync(test, tenant);
        var key = Guid.NewGuid();
        var service = new WebCheckoutService(test.Db);
        var ctx = Context(tenant);
        var lines = new[] { new WebCheckoutLine(product.GlobalId, 1) };
        var payments = new[] { new WebCheckoutPayment("Cash", 100) };
        await service.CheckoutAsync(new(key, lines, payments, 110), ctx, TestContext.Current.CancellationToken);
        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            service.CheckoutAsync(new(key, lines, payments, 120), ctx, TestContext.Current.CancellationToken));
        test.Db.ChangeTracker.Clear();
        Assert.Equal(1, await test.Db.Sales.CountAsync());
        Assert.Equal(1, await test.Db.InventoryMovements.CountAsync());
        Assert.Equal(1, await test.Db.SyncChanges.CountAsync());
    }

    [Fact]
    public async Task Concurrent_same_key_creates_one_sale_payment_fifo_and_cash_movement()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB_CONCURRENT");
        var (product, oldLot, newLot) = await SeedLotsAsync(test, tenant);
        var request = new WebCheckoutRequest(Guid.NewGuid(),
            [new WebCheckoutLine(product.GlobalId, 3)],
            [new WebCheckoutPayment("Cash", 300)], 300);
        await using var firstDb = test.CreateDbContext();
        await using var secondDb = test.CreateDbContext();

        var results = await Task.WhenAll(
            new WebCheckoutService(firstDb).CheckoutAsync(request, Context(tenant), TestContext.Current.CancellationToken),
            new WebCheckoutService(secondDb).CheckoutAsync(request, Context(tenant), TestContext.Current.CancellationToken));

        Assert.Equal(results[0].SaleGlobalId, results[1].SaleGlobalId);
        Assert.Contains(results, result => result.AlreadyProcessed);
        test.Db.ChangeTracker.Clear();
        Assert.Single(await test.Db.Sales.ToListAsync());
        Assert.Single(await test.Db.SalePayments.ToListAsync());
        Assert.Single(await test.Db.InventoryMovements.ToListAsync());
        Assert.Single(await test.Db.SyncChanges.ToListAsync());
        Assert.Equal(0, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == oldLot.GlobalId)).AvailableQuantity);
        Assert.Equal(3, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == newLot.GlobalId)).AvailableQuantity);
    }

    [Fact]
    public async Task Invalid_payment_rolls_back_lots_sale_and_movements()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB3");
        var (product, oldLot, newLot) = await SeedLotsAsync(test, tenant);
        var service = new WebCheckoutService(test.Db);
        await Assert.ThrowsAsync<ArgumentException>(() => service.CheckoutAsync(
            new(Guid.NewGuid(), [new WebCheckoutLine(product.GlobalId, 3)],
                [new WebCheckoutPayment("Card", 299)]),
            Context(tenant), TestContext.Current.CancellationToken));
        test.Db.ChangeTracker.Clear();
        Assert.Empty(await test.Db.Sales.ToListAsync());
        Assert.Empty(await test.Db.SalePayments.ToListAsync());
        Assert.Empty(await test.Db.InventoryMovements.ToListAsync());
        Assert.Empty(await test.Db.SyncChanges.ToListAsync());
        Assert.Equal(2, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == oldLot.GlobalId)).AvailableQuantity);
        Assert.Equal(4, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == newLot.GlobalId)).AvailableQuantity);
    }

    [Fact]
    public async Task Sale_without_stock_does_not_persist_anything()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB4");
        var (product, _, _) = await SeedLotsAsync(test, tenant);
        await Assert.ThrowsAsync<InvalidOperationException>(() => new WebCheckoutService(test.Db).CheckoutAsync(
            new(Guid.NewGuid(), [new WebCheckoutLine(product.GlobalId, 7)],
                [new WebCheckoutPayment("Card", 700)]), Context(tenant), TestContext.Current.CancellationToken));
        test.Db.ChangeTracker.Clear();
        Assert.Equal(0, await test.Db.Sales.CountAsync());
        Assert.Equal(0, await test.Db.InventoryMovements.CountAsync());
        Assert.Equal(0, await test.Db.SyncChanges.CountAsync());
    }

    [Fact]
    public async Task Cash_payment_requires_exactly_one_open_cash_session()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB5");
        var (product, oldLot, newLot) = await SeedLotsAsync(test, tenant);
        test.Db.RemoveRange(await test.Db.CashSessions.ToListAsync());
        await test.Db.SaveChangesAsync();

        await Assert.ThrowsAsync<InvalidOperationException>(() => new WebCheckoutService(test.Db).CheckoutAsync(
            new(Guid.NewGuid(), [new WebCheckoutLine(product.GlobalId, 1)],
                [new WebCheckoutPayment("Cash", 100)], 100), Context(tenant), TestContext.Current.CancellationToken));
        test.Db.ChangeTracker.Clear();
        Assert.Empty(await test.Db.Sales.ToListAsync());
        Assert.Empty(await test.Db.SalePayments.ToListAsync());
        Assert.Equal(2, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == oldLot.GlobalId)).AvailableQuantity);
        Assert.Equal(4, (await test.Db.InventoryLots.SingleAsync(x => x.GlobalId == newLot.GlobalId)).AvailableQuantity);
    }

    [Fact]
    public async Task Non_cash_payment_does_not_require_or_link_a_cash_session()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("WEB6");
        var (product, _, _) = await SeedLotsAsync(test, tenant);
        test.Db.RemoveRange(await test.Db.CashSessions.ToListAsync());
        await test.Db.SaveChangesAsync();

        await new WebCheckoutService(test.Db).CheckoutAsync(
            new(Guid.NewGuid(), [new WebCheckoutLine(product.GlobalId, 1)],
                [new WebCheckoutPayment("Card", 100)]), Context(tenant), TestContext.Current.CancellationToken);
        test.Db.ChangeTracker.Clear();
        Assert.Null((await test.Db.SalePayments.SingleAsync()).CashSessionId);
    }

    private static SyncTenantContext Context((Business Business, Branch Branch, Device Device, UserAccount User) t) =>
        new(t.Business.Id, t.Business.GlobalId, t.Branch.Id, t.Branch.GlobalId,
            t.Device.Id, t.Device.GlobalId, t.User.Id, t.User.GlobalId, t.User.Role, t.Device.Mode);

    private static async Task<(Product Product, InventoryLot OldLot, InventoryLot NewLot)> SeedLotsAsync(
        SqlServerTestDatabase test, (Business Business, Branch Branch, Device Device, UserAccount User) tenant)
    {
        var now = DateTimeOffset.UtcNow;
        var product = new Product { GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id,
            Code = Guid.NewGuid().ToString("N"), Name = "Web test item", SalePriceCents = 100, Active = true, UpdatedAt = now };
        var oldLot = new InventoryLot { GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id, ProductGlobalId = product.GlobalId,
            EntryDate = now.AddDays(-2), InitialQuantity = 2, AvailableQuantity = 2, UnitCostCents = 10, Active = true, CreatedAt = now };
        var newLot = new InventoryLot { GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id, ProductGlobalId = product.GlobalId,
            EntryDate = now.AddDays(-1), InitialQuantity = 4, AvailableQuantity = 4, UnitCostCents = 30, Active = true, CreatedAt = now };
        var cash = new CashSession { GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id, DeviceId = tenant.Device.Id, UserId = tenant.User.Id,
            OpenedAt = now, OpeningBalanceCents = 0, Status = "Open", UpdatedAt = now };
        test.Db.AddRange(product, oldLot, newLot, cash);
        await test.Db.SaveChangesAsync();
        return (product, oldLot, newLot);
    }
}
