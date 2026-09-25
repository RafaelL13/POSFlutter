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

        var syncChange = await t.Db.SyncChanges.SingleAsync(x =>
            x.BusinessId == tenant.Business.Id &&
            x.EntityType == "CentralTransferIn" &&
            x.EntityGlobalId == transferId);
        Assert.Equal("Create", syncChange.Operation);
        Assert.Equal(1, syncChange.Version);
        using var syncPayload = System.Text.Json.JsonDocument.Parse(syncChange.PayloadJson);
        var root = syncPayload.RootElement;
        Assert.Equal(transferId, root.GetProperty("globalId").GetGuid());
        Assert.Equal(tenant.Business.GlobalId, root.GetProperty("businessGlobalId").GetGuid());
        Assert.Equal(tenant.Branch.GlobalId, root.GetProperty("branchGlobalId").GetGuid());
        Assert.Equal(1, root.GetProperty("serverVersion").GetInt64());
        var lines = root.GetProperty("lines");
        Assert.Equal(1, lines.GetArrayLength());
        Assert.Equal(product.GlobalId, lines[0].GetProperty("productGlobalId").GetGuid());
        Assert.Equal(lotId, lines[0].GetProperty("lotGlobalId").GetGuid());
        Assert.Equal(7, lines[0].GetProperty("quantity").GetInt32());
        Assert.Equal(1234, lines[0].GetProperty("unitCostCents").GetInt64());
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
        Assert.Single(await t.Db.SyncChanges.Where(x =>
            x.EntityType == "CentralTransferIn" &&
            x.EntityGlobalId == request.TransferGlobalId).ToListAsync());
    }

    [Fact]
    public async Task Published_transfer_is_pullable_with_exact_contract()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync();
        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "CENTRAL-PULL",
            Name = "Central pull product",
            Presentation = "Piece",
            Active = true,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        t.Db.Products.Add(product);
        await t.Db.SaveChangesAsync();

        var transferId = Guid.NewGuid();
        var lotId = Guid.NewGuid();
        var date = DateTimeOffset.Parse("2026-09-25T02:00:00Z");
        var service = new CentralInventoryTransferService(t.Db);
        await service.ReceiveAsync(
            new CentralTransferInRequest(
                transferId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                date,
                [new CentralTransferInLine(product.GlobalId, lotId, 5, 987)]),
            CancellationToken.None);

        var sync = new SyncService(t.Db);
        var context = new SyncTenantContext(
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

        var pull = await sync.PullAsync(0, 200, context, CancellationToken.None);
        var change = Assert.Single(pull.Changes.Where(x =>
            x.EntityType == "CentralTransferIn" &&
            x.EntityGlobalId == transferId));

        Assert.Equal("Create", change.Operation);
        Assert.Equal(1, change.Version);
        var payload = change.Payload;
        Assert.Equal(transferId, payload.GetProperty("globalId").GetGuid());
        Assert.Equal(tenant.Business.GlobalId, payload.GetProperty("businessGlobalId").GetGuid());
        Assert.Equal(tenant.Branch.GlobalId, payload.GetProperty("branchGlobalId").GetGuid());
        Assert.Equal(date, payload.GetProperty("date").GetDateTimeOffset());
        var lines = payload.GetProperty("lines");
        Assert.Equal(1, lines.GetArrayLength());
        Assert.Equal(product.GlobalId, lines[0].GetProperty("productGlobalId").GetGuid());
        Assert.Equal(lotId, lines[0].GetProperty("lotGlobalId").GetGuid());
        Assert.Equal(5, lines[0].GetProperty("quantity").GetInt32());
        Assert.Equal(987, lines[0].GetProperty("unitCostCents").GetInt64());
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

    [Fact]
    public async Task Concurrent_same_transfer_is_idempotent_on_sql_server()
    {
        await using var t = await SqlServerTestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync("CENTRAL-RACE");

        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "CENTRAL-RACE",
            Name = "Central race product",
            Presentation = "Piece",
            Active = true,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        t.Db.Products.Add(product);
        await t.Db.SaveChangesAsync(TestContext.Current.CancellationToken);

        var request = new CentralTransferInRequest(
            Guid.NewGuid(),
            tenant.Business.GlobalId,
            tenant.Branch.GlobalId,
            DateTimeOffset.UtcNow,
            [
                new CentralTransferInLine(
                    product.GlobalId,
                    Guid.NewGuid(),
                    4,
                    725)
            ]);

        await using var dbA = t.CreateDbContext();
        await using var dbB = t.CreateDbContext();

        var serviceA = new CentralInventoryTransferService(dbA);
        var serviceB = new CentralInventoryTransferService(dbB);

        using var gate = new Barrier(2);

        async Task<CentralTransferInResult> ReceiveAsync(
            CentralInventoryTransferService service)
        {
            await Task.Yield();
            gate.SignalAndWait(TimeSpan.FromSeconds(10));

            return await service.ReceiveAsync(
                request,
                CancellationToken.None);
        }

        var taskA = ReceiveAsync(serviceA);
        var taskB = ReceiveAsync(serviceB);

        var results = await Task.WhenAll(taskA, taskB);

        Assert.Equal(2, results.Length);
        Assert.All(results, result => Assert.True(result.Succeeded));
        Assert.Single(results, result => !result.AlreadyReceived);
        Assert.Single(results, result => result.AlreadyReceived);

        await using var verify = t.CreateDbContext();

        Assert.Single(
            await verify.InventoryLots
                .Where(x =>
                    x.BusinessId == tenant.Business.Id &&
                    x.ProductGlobalId == product.GlobalId)
                .ToListAsync(cancellationToken: TestContext.Current.CancellationToken));

        Assert.Single(
            await verify.InventoryMovements
                .Where(x =>
                    x.BusinessId == tenant.Business.Id &&
                    x.ReferenceGlobalId == request.TransferGlobalId)
                .ToListAsync(cancellationToken: TestContext.Current.CancellationToken));

        Assert.Single(
            await verify.CentralInventoryTransferReceipts
                .Where(x =>
                    x.BusinessId == tenant.Business.Id &&
                    x.TransferGlobalId == request.TransferGlobalId)
                .ToListAsync(cancellationToken: TestContext.Current.CancellationToken));

        Assert.Single(
            await verify.SyncChanges
                .Where(x =>
                    x.BusinessId == tenant.Business.Id &&
                    x.EntityType == "CentralTransferIn" &&
                    x.EntityGlobalId == request.TransferGlobalId)
                .ToListAsync(cancellationToken: TestContext.Current.CancellationToken));
    }
}
