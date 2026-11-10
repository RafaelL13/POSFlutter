using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

public sealed class WebSaleCancellationSqlTests
{
    [Fact]
    public async Task Cash_sale_cancellation_restores_original_lot_once_and_publishes_cancel()
    {
        await using var test=await SqlServerTestDatabase.CreateAsync(); var t=await test.SeedTenantAsync("CANWEB"); var now=DateTimeOffset.UtcNow;
        var product=new Product{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,Code="C"+Guid.NewGuid().ToString("N"),Name="Cancel",SalePriceCents=100,Active=true,UpdatedAt=now};
        var lot=new InventoryLot{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,BranchId=t.Branch.Id,ProductGlobalId=product.GlobalId,EntryDate=now,InitialQuantity=3,AvailableQuantity=3,UnitCostCents=40,Active=true,CreatedAt=now};
        var cash=new CashSession{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,BranchId=t.Branch.Id,DeviceId=t.Device.Id,UserId=t.User.Id,OpenedAt=now,Status="Open",UpdatedAt=now};test.Db.AddRange(product,lot,cash);await test.Db.SaveChangesAsync();
        var ctx=new SyncTenantContext(t.Business.Id,t.Business.GlobalId,t.Branch.Id,t.Branch.GlobalId,t.Device.Id,t.Device.GlobalId,t.User.Id,t.User.GlobalId,t.User.Role,t.Device.Mode);
        var sale=await new WebCheckoutService(test.Db).CheckoutAsync(new(Guid.NewGuid(),[new WebCheckoutLine(product.GlobalId,2)],[new WebCheckoutPayment("Cash",200)],200),ctx,TestContext.Current.CancellationToken);
        var first=await new WebSaleCancellationService(test.Db).CancelAsync(new(sale.SaleGlobalId,"test refund"),ctx,TestContext.Current.CancellationToken);
        var replay=await new WebSaleCancellationService(test.Db).CancelAsync(new(sale.SaleGlobalId,"test refund"),ctx,TestContext.Current.CancellationToken);
        test.Db.ChangeTracker.Clear();Assert.False(first.AlreadyCancelled);Assert.True(replay.AlreadyCancelled);Assert.Equal(3,(await test.Db.InventoryLots.SingleAsync()).AvailableQuantity);Assert.Single(await test.Db.InventoryMovements.Where(x=>x.Type=="Cancellation").ToListAsync());Assert.Single(await test.Db.CashMovements.Where(x=>x.Type=="ManualOut"&&x.AmountCents==-200).ToListAsync());Assert.Single(await test.Db.SyncChanges.Where(x=>x.EntityGlobalId==sale.SaleGlobalId&&x.Operation=="Cancel").ToListAsync());
    }

    [Fact]
    public async Task Cancellation_fails_closed_for_foreign_actor_closed_cash_and_card_refund()
    {
        await using var test=await SqlServerTestDatabase.CreateAsync(); var t=await test.SeedTenantAsync("CANNEG"); var foreign=await test.SeedTenantAsync("CANFOREIGN"); var now=DateTimeOffset.UtcNow;
        var product=new Product{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,Code="N"+Guid.NewGuid().ToString("N"),Name="Negative",SalePriceCents=100,Active=true,UpdatedAt=now};
        var lot=new InventoryLot{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,BranchId=t.Branch.Id,ProductGlobalId=product.GlobalId,EntryDate=now,InitialQuantity=4,AvailableQuantity=4,UnitCostCents=20,Active=true,CreatedAt=now};
        var cash=new CashSession{GlobalId=Guid.NewGuid(),BusinessId=t.Business.Id,BranchId=t.Branch.Id,DeviceId=t.Device.Id,UserId=t.User.Id,OpenedAt=now,Status="Open",UpdatedAt=now};test.Db.AddRange(product,lot,cash);await test.Db.SaveChangesAsync();
        var ctx=new SyncTenantContext(t.Business.Id,t.Business.GlobalId,t.Branch.Id,t.Branch.GlobalId,t.Device.Id,t.Device.GlobalId,t.User.Id,t.User.GlobalId,t.User.Role,t.Device.Mode);
        var foreignCtx=new SyncTenantContext(foreign.Business.Id,foreign.Business.GlobalId,foreign.Branch.Id,foreign.Branch.GlobalId,foreign.Device.Id,foreign.Device.GlobalId,foreign.User.Id,foreign.User.GlobalId,foreign.User.Role,foreign.Device.Mode);
        var checkout=new WebCheckoutService(test.Db);var service=new WebSaleCancellationService(test.Db);
        var card=await checkout.CheckoutAsync(new(Guid.NewGuid(),[new WebCheckoutLine(product.GlobalId,1)],[new WebCheckoutPayment("Card",100)]),ctx,TestContext.Current.CancellationToken);
        await Assert.ThrowsAsync<KeyNotFoundException>(()=>service.CancelAsync(new(card.SaleGlobalId,"foreign"),foreignCtx,TestContext.Current.CancellationToken));
        await Assert.ThrowsAsync<InvalidOperationException>(()=>service.CancelAsync(new(card.SaleGlobalId,"card"),ctx,TestContext.Current.CancellationToken));
        var cashSale=await checkout.CheckoutAsync(new(Guid.NewGuid(),[new WebCheckoutLine(product.GlobalId,1)],[new WebCheckoutPayment("Cash",100)],100),ctx,TestContext.Current.CancellationToken);
        (await test.Db.CashSessions.SingleAsync()).Status="Closed";await test.Db.SaveChangesAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(()=>service.CancelAsync(new(cashSale.SaleGlobalId,"closed"),ctx,TestContext.Current.CancellationToken));
        test.Db.ChangeTracker.Clear();Assert.Equal(2,await test.Db.Sales.CountAsync(x=>x.Status=="Confirmed"));Assert.Empty(await test.Db.InventoryMovements.Where(x=>x.Type=="Cancellation").ToListAsync());
    }
}
