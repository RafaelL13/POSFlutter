using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class SalePaymentTests
{
    [Fact]
    public async Task Mixed_sale_is_atomic_and_duplicate_retry_does_not_duplicate_payments()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("PAY");
        var (product,lot) = await SeedInventoryAsync(test,tenant);
        var operationId = Guid.NewGuid();
        var saleId = Guid.NewGuid();
        var operation = SaleOperation(operationId,saleId,tenant,product,lot,
        new object[]
        {
            new { globalId = Guid.NewGuid(),method = "Cash",amountCents = 20L },
            new { globalId = Guid.NewGuid(),method = "Card",amountCents = 30L },
            new { globalId = Guid.NewGuid(),method = "Transfer",amountCents = 50L }
        },receivedCents:25,changeCents:5);
        var service = new SyncService(test.Db);
        var context = Context(tenant);

        var first = await service.PushAsync(new SyncPushRequest([operation]),context,CancellationToken.None);
        var retry = await service.PushAsync(new SyncPushRequest([operation]),context,CancellationToken.None);

        Assert.True(first.Results.Single().Status == "Applied",first.Results.Single().Error);
        Assert.Equal("AlreadyProcessed",retry.Results.Single().Status);
        var sale = await test.Db.Sales.Include(x => x.Payments).SingleAsync(x => x.GlobalId == saleId);
        Assert.Equal("Mixed",sale.PaymentMethod);
        Assert.Equal(3,sale.Payments.Count);
        Assert.Equal(100,sale.Payments.Sum(x => x.AmountCents));
        Assert.Single(test.Db.Sales.Where(x => x.GlobalId == saleId));
    }

    [Fact]
    public async Task Invalid_payment_sum_rolls_back_sale_inventory_and_inbound_operation()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("BAD");
        var (product,lot) = await SeedInventoryAsync(test,tenant);
        var operation = SaleOperation(Guid.NewGuid(),Guid.NewGuid(),tenant,product,lot,
        new object[] { new { globalId = Guid.NewGuid(),method = "Card",amountCents = 99L } });

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),Context(tenant),CancellationToken.None);

        Assert.Equal("Rejected",response.Results.Single().Status);
        Assert.Empty(test.Db.Sales);
        Assert.Empty(test.Db.SalePayments);
        Assert.Equal(5,(await test.Db.InventoryLots.SingleAsync()).AvailableQuantity);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Legacy_v1_cash_payload_creates_one_payment()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("LEG");
        var (product,lot) = await SeedInventoryAsync(test,tenant);
        var operation = SaleOperation(Guid.NewGuid(),Guid.NewGuid(),tenant,product,lot,null,payloadVersion:1,receivedCents:120,changeCents:20);

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),Context(tenant),CancellationToken.None);

        Assert.Equal("Applied",response.Results.Single().Status);
        var payment = Assert.Single(test.Db.SalePayments);
        Assert.Equal("Cash",payment.Method);
        Assert.Equal(100,payment.AmountCents);
    }

    [Fact]
    public async Task Cancellation_preserves_payment_trace_and_restores_fifo_stock()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CAN");
        var (product,lot) = await SeedInventoryAsync(test,tenant);
        var saleId = Guid.NewGuid();
        var service = new SyncService(test.Db);
        var created = await service.PushAsync(new SyncPushRequest([SaleOperation(
            Guid.NewGuid(),saleId,tenant,product,lot,
            new object[] { new { globalId = Guid.NewGuid(),method = "Cash",amountCents = 40L },new { globalId = Guid.NewGuid(),method = "Card",amountCents = 60L } },
            receivedCents:40)]),Context(tenant),TestContext.Current.CancellationToken);
        Assert.Equal("Applied",created.Results.Single().Status);

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            globalId = saleId,deviceGlobalId = tenant.Device.GlobalId,userGlobalId = tenant.User.GlobalId,
            cancelledAt = DateTimeOffset.UtcNow,reason = "Test cancellation"
        }));
        var cancelled = await service.PushAsync(new SyncPushRequest([
            new SyncOperationDto(Guid.NewGuid(),"Sale",saleId,"Cancel",1,document.RootElement.Clone())
        ]),Context(tenant),TestContext.Current.CancellationToken);

        Assert.Equal("Applied",cancelled.Results.Single().Status);
        Assert.Equal("Cancelled",(await test.Db.Sales.SingleAsync(x => x.GlobalId == saleId)).Status);
        Assert.Equal(2,await test.Db.SalePayments.CountAsync(x => x.SaleId == test.Db.Sales.Single(s => s.GlobalId == saleId).Id));
        Assert.Equal(5,(await test.Db.InventoryLots.SingleAsync()).AvailableQuantity);
    }

    private static SyncTenantContext Context((Business Business,Branch Branch,Device Device,UserAccount User) tenant) =>
        new(tenant.Business.Id,tenant.Business.GlobalId,tenant.Branch.Id,tenant.Branch.GlobalId,tenant.Device.Id,tenant.Device.GlobalId,tenant.User.Id,tenant.User.GlobalId,tenant.User.Role,tenant.Device.Mode);

    private static async Task<(Product Product,InventoryLot Lot)> SeedInventoryAsync(TestDatabase test,(Business Business,Branch Branch,Device Device,UserAccount User) tenant)
    {
        var now = DateTimeOffset.UtcNow;
        var product = new Product { GlobalId = Guid.NewGuid(),BusinessId = tenant.Business.Id,Code = Guid.NewGuid().ToString("N"),Name = "Product",SalePriceCents = 100,UpdatedAt = now };
        var lot = new InventoryLot { GlobalId = Guid.NewGuid(),BusinessId = tenant.Business.Id,BranchId = tenant.Branch.Id,ProductGlobalId = product.GlobalId,EntryDate = now,InitialQuantity = 5,AvailableQuantity = 5,UnitCostCents = 40,CreatedAt = now };
        test.Db.AddRange(product,lot); await test.Db.SaveChangesAsync(); return(product,lot);
    }

    private static SyncOperationDto SaleOperation(Guid operationId,Guid saleId,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,Product product,InventoryLot lot,object? payments,int payloadVersion=2,long? receivedCents=null,long changeCents=0)
    {
        var payload = new
        {
            globalId=saleId,idempotencyKey=Guid.NewGuid(),businessGlobalId=tenant.Business.GlobalId,branchGlobalId=tenant.Branch.GlobalId,deviceGlobalId=tenant.Device.GlobalId,userGlobalId=tenant.User.GlobalId,
            folio=Guid.NewGuid().ToString("N"),saleDateTime=DateTimeOffset.UtcNow,subtotalCents=100L,discountCents=0L,totalCents=100L,fifoCostCents=40L,grossProfitCents=60L,
            paymentMethod="Cash",receivedCents,changeCents,payments,
            lines=new[]{new{detailGlobalId=Guid.NewGuid(),productGlobalId=product.GlobalId,quantity=1,unitPriceCents=100L,totalCents=100L,fifoCostCents=40L,lots=new[]{new{globalId=Guid.NewGuid(),lotGlobalId=lot.GlobalId,quantity=1,unitCostCents=40L,totalCostCents=40L}}}}
        };
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(payload));
        return new SyncOperationDto(operationId,"Sale",saleId,"Create",payloadVersion,document.RootElement.Clone());
    }

}
