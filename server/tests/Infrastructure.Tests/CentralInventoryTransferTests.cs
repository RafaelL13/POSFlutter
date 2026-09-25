using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class CentralInventoryTransferTests
{
    [Fact]
    public async Task Receive_creates_exact_lot_movement_and_receipt()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync();
        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "CENTRAL-1",
            Name = "Central product",
            Presentation = "Piece",
            Active = true,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        t.Db.Products.Add(product);
        await t.Db.SaveChangesAsync();

        var transferId = Guid.NewGuid();
        var lotId = Guid.NewGuid();
        var service = new CentralInventoryTransferService(t.Db);
        var result = await service.ReceiveAsync(
            new CentralTransferInRequest(
                transferId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                DateTimeOffset.UtcNow,
                [new CentralTransferInLine(product.GlobalId, lotId, 7, 1234)]),
            CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.False(result.AlreadyReceived);
        var lot = await t.Db.InventoryLots.SingleAsync(x => x.GlobalId == lotId);
        Assert.Equal(7, lot.InitialQuantity);
        Assert.Equal(7, lot.AvailableQuantity);
        Assert.Equal(1234, lot.UnitCostCents);
        var movement = await t.Db.InventoryMovements.SingleAsync(x => x.ReferenceGlobalId == transferId);
        Assert.Equal("CentralTransferIn", movement.Type);
        Assert.Equal(7, movement.QuantityDelta);
        Assert.Equal(0, movement.PreviousStock);
        Assert.Equal(7, movement.NewStock);
        Assert.Equal(tenant.User.Id, movement.UserId);
        Assert.Equal(tenant.Device.Id, movement.DeviceId);
        Assert.Single(await t.Db.CentralInventoryTransferReceipts.Where(x => x.TransferGlobalId == transferId).ToListAsync());
    }

    [Fact]
    public async Task Retry_is_idempotent_and_does_not_duplicate_inventory()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync();
        var product = new Product
        {
            GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id, Code = "CENTRAL-2",
            Name = "Central product", Presentation = "Piece", Active = true, UpdatedAt = DateTimeOffset.UtcNow
        };
        t.Db.Products.Add(product);
        await t.Db.SaveChangesAsync();
        var request = new CentralTransferInRequest(
            Guid.NewGuid(), tenant.Business.GlobalId, tenant.Branch.GlobalId, DateTimeOffset.UtcNow,
            [new CentralTransferInLine(product.GlobalId, Guid.NewGuid(), 3, 500)]);
        var service = new CentralInventoryTransferService(t.Db);

        var first = await service.ReceiveAsync(request, CancellationToken.None);
        var second = await service.ReceiveAsync(request, CancellationToken.None);

        Assert.False(first.AlreadyReceived);
        Assert.True(second.AlreadyReceived);
        Assert.Single(await t.Db.InventoryLots.Where(x => x.ProductGlobalId == product.GlobalId).ToListAsync());
        Assert.Single(await t.Db.InventoryMovements.Where(x => x.ReferenceGlobalId == request.TransferGlobalId).ToListAsync());
        Assert.Single(await t.Db.CentralInventoryTransferReceipts.Where(x => x.TransferGlobalId == request.TransferGlobalId).ToListAsync());
    }

    [Fact]
    public async Task Invalid_transfer_does_not_mutate_inventory()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync();
        var service = new CentralInventoryTransferService(t.Db);
        var request = new CentralTransferInRequest(
            Guid.NewGuid(), tenant.Business.GlobalId, tenant.Branch.GlobalId, DateTimeOffset.UtcNow,
            [new CentralTransferInLine(Guid.NewGuid(), Guid.NewGuid(), 1, 100)]);

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.ReceiveAsync(request, CancellationToken.None));

        Assert.Empty(await t.Db.InventoryLots.ToListAsync());
        Assert.Empty(await t.Db.InventoryMovements.ToListAsync());
        Assert.Empty(await t.Db.CentralInventoryTransferReceipts.ToListAsync());
    }
}
