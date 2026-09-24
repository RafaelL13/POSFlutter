using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class InitialInventorySyncTests
{
    [Fact]
    public async Task Manager_applies_initial_inventory_with_fifo_lot_movement_and_line()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("INIT-MANAGER", role: "Manager");
        var product = await AddProductAsync(test, tenant, "P001");

        var inventoryId = Guid.NewGuid();
        var lineId = Guid.NewGuid();
        var lotId = Guid.NewGuid();

        var result = await PushAsync(
            test,
            tenant,
            Operation(
                Guid.NewGuid(),
                inventoryId,
                tenant,
                "fingerprint-manager-001",
                new[]
                {
                    Line(lineId, product.GlobalId, lotId, 10, 10000L)
                }));

        Assert.Equal("Applied", result.Status);

        var inventory = await test.Db.InitialInventories
            .Include(x => x.Lines)
            .SingleAsync(
                x => x.GlobalId == inventoryId,
                TestContext.Current.CancellationToken);

        Assert.Equal(tenant.Business.Id, inventory.BusinessId);
        Assert.Equal(tenant.Branch.Id, inventory.BranchId);
        Assert.Equal(tenant.Device.Id, inventory.DeviceId);
        Assert.Equal(tenant.User.Id, inventory.UserId);
        Assert.Equal("fingerprint-manager-001", inventory.SourceFingerprint);
        Assert.Equal(1, inventory.ValidRows);
        Assert.Equal(10, inventory.TotalUnits);

        var line = Assert.Single(inventory.Lines);
        Assert.Equal(lineId, line.GlobalId);
        Assert.Equal(product.GlobalId, line.ProductGlobalId);
        Assert.Equal(lotId, line.InventoryLotGlobalId);
        Assert.Equal(10, line.Quantity);
        Assert.Equal(10000L, line.UnitCostCents);

        var lot = await test.Db.InventoryLots.SingleAsync(
            x => x.GlobalId == lotId,
            TestContext.Current.CancellationToken);

        Assert.Equal(10, lot.InitialQuantity);
        Assert.Equal(10, lot.AvailableQuantity);
        Assert.Equal(10000L, lot.UnitCostCents);
        Assert.True(lot.Active);
        Assert.Equal(tenant.Branch.Id, lot.BranchId);
        Assert.Equal(product.GlobalId, lot.ProductGlobalId);

        var movement = await test.Db.InventoryMovements.SingleAsync(
            x => x.ReferenceGlobalId == inventoryId,
            TestContext.Current.CancellationToken);

        Assert.Equal("InitialInventory", movement.Type);
        Assert.Equal(10, movement.QuantityDelta);
        Assert.Equal(0, movement.PreviousStock);
        Assert.Equal(10, movement.NewStock);
        Assert.Equal(product.GlobalId, movement.ProductGlobalId);

        Assert.Single(test.Db.InboundOperations);
        Assert.Contains(
            test.Db.SyncChanges,
            x => x.EntityType == "InitialInventory"
                 && x.EntityGlobalId == inventoryId
                 && x.Operation == "Create");
    }

    [Fact]
    public async Task Repeated_same_operation_is_idempotent()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("INIT-RETRY", role: "Manager");
        var product = await AddProductAsync(test, tenant, "P002");

        var operationId = Guid.NewGuid();
        var inventoryId = Guid.NewGuid();
        var lotId = Guid.NewGuid();

        var operation = Operation(
            operationId,
            inventoryId,
            tenant,
            "fingerprint-retry-001",
            new[]
            {
                Line(Guid.NewGuid(), product.GlobalId, lotId, 7, 2500L)
            });

        var service = new SyncService(test.Db);

        var first = await service.PushAsync(
            new SyncPushRequest([operation]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var second = await service.PushAsync(
            new SyncPushRequest([operation]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        Assert.Equal("Applied", Assert.Single(first.Results).Status);
        Assert.Equal("AlreadyProcessed", Assert.Single(second.Results).Status);

        Assert.Single(test.Db.InitialInventories);
        Assert.Single(test.Db.InitialInventoryLines);
        Assert.Single(test.Db.InventoryLots.Where(x => x.GlobalId == lotId));
        Assert.Single(test.Db.InventoryMovements.Where(
            x => x.ReferenceGlobalId == inventoryId));
        Assert.Single(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Same_fingerprint_with_different_inventory_id_is_rejected_without_duplicate_stock()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("INIT-FINGERPRINT", role: "Manager");
        var product = await AddProductAsync(test, tenant, "P003");

        const string fingerprint = "fingerprint-duplicate-001";

        var firstId = Guid.NewGuid();
        var firstLot = Guid.NewGuid();

        var first = await PushAsync(
            test,
            tenant,
            Operation(
                Guid.NewGuid(),
                firstId,
                tenant,
                fingerprint,
                new[]
                {
                    Line(Guid.NewGuid(), product.GlobalId, firstLot, 5, 4000L)
                }));

        Assert.Equal("Applied", first.Status);

        var secondId = Guid.NewGuid();
        var secondLot = Guid.NewGuid();

        var second = await PushAsync(
            test,
            tenant,
            Operation(
                Guid.NewGuid(),
                secondId,
                tenant,
                fingerprint,
                new[]
                {
                    Line(Guid.NewGuid(), product.GlobalId, secondLot, 5, 4000L)
                }));

        Assert.Equal("Rejected", second.Status);
        Assert.Equal(SyncErrorCodes.ValidationFailed, second.ErrorCode);

        Assert.Single(test.Db.InitialInventories);
        Assert.Single(test.Db.InitialInventoryLines);

        var lots = await test.Db.InventoryLots
            .Where(x => x.ProductGlobalId == product.GlobalId)
            .ToListAsync(TestContext.Current.CancellationToken);

        Assert.Single(lots);
        Assert.Equal(firstLot, lots[0].GlobalId);
        Assert.Equal(5, lots[0].AvailableQuantity);

        Assert.DoesNotContain(
            test.Db.InventoryLots,
            x => x.GlobalId == secondLot);

        Assert.Single(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Same_fingerprint_is_scoped_by_business_and_branch()
    {
        await using var test = await TestDatabase.CreateAsync();

        var tenantA = await test.SeedTenantAsync("INIT-A", role: "Manager");
        var tenantB = await test.SeedTenantAsync("INIT-B", role: "Manager");

        var productA = await AddProductAsync(test, tenantA, "P-A");
        var productB = await AddProductAsync(test, tenantB, "P-B");

        const string fingerprint = "shared-fingerprint";

        var resultA = await PushAsync(
            test,
            tenantA,
            Operation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                tenantA,
                fingerprint,
                new[]
                {
                    Line(
                        Guid.NewGuid(),
                        productA.GlobalId,
                        Guid.NewGuid(),
                        3,
                        1000L)
                }));

        var resultB = await PushAsync(
            test,
            tenantB,
            Operation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                tenantB,
                fingerprint,
                new[]
                {
                    Line(
                        Guid.NewGuid(),
                        productB.GlobalId,
                        Guid.NewGuid(),
                        4,
                        2000L)
                }));

        Assert.Equal("Applied", resultA.Status);
        Assert.Equal("Applied", resultB.Status);
        Assert.Equal(2, await test.Db.InitialInventories.CountAsync(
            TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Historical_manager_actor_is_preserved()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync(
            "INIT-HISTORICAL",
            role: "Administrator");

        var historical = await AddUserAsync(
            test,
            tenant.Business,
            "Manager",
            "Historical Manager");

        var product = await AddProductAsync(test, tenant, "P004");
        var inventoryId = Guid.NewGuid();

        var operation = Operation(
            Guid.NewGuid(),
            inventoryId,
            tenant,
            "fingerprint-historical-001",
            new[]
            {
                Line(
                    Guid.NewGuid(),
                    product.GlobalId,
                    Guid.NewGuid(),
                    8,
                    3000L)
            },
            historical.GlobalId);

        var result = await PushAsync(test, tenant, operation);

        Assert.Equal("Applied", result.Status);

        var stored = await test.Db.InitialInventories.SingleAsync(
            x => x.GlobalId == inventoryId,
            TestContext.Current.CancellationToken);

        Assert.Equal(historical.Id, stored.UserId);
        Assert.NotEqual(tenant.User.Id, stored.UserId);

        var movement = await test.Db.InventoryMovements.SingleAsync(
            x => x.ReferenceGlobalId == inventoryId,
            TestContext.Current.CancellationToken);

        Assert.Equal(historical.Id, movement.UserId);
    }

    [Fact]
    public async Task Seller_cannot_sync_initial_inventory()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync(
            "INIT-SELLER",
            role: "Seller");

        var product = await AddProductAsync(test, tenant, "P005");
        var inventoryId = Guid.NewGuid();

        var result = await PushAsync(
            test,
            tenant,
            Operation(
                Guid.NewGuid(),
                inventoryId,
                tenant,
                "fingerprint-seller-001",
                new[]
                {
                    Line(
                        Guid.NewGuid(),
                        product.GlobalId,
                        Guid.NewGuid(),
                        5,
                        1000L)
                }));

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.RoleDenied, result.ErrorCode);

        Assert.Empty(test.Db.InitialInventories);
        Assert.Empty(test.Db.InitialInventoryLines);
        Assert.Empty(test.Db.InventoryLots);
        Assert.Empty(test.Db.InventoryMovements);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Invalid_second_line_rolls_back_entire_operation()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync(
            "INIT-ROLLBACK",
            role: "Manager");

        var productA = await AddProductAsync(test, tenant, "P006-A");
        var productB = await AddProductAsync(test, tenant, "P006-B");

        var inventoryId = Guid.NewGuid();
        var validLot = Guid.NewGuid();
        var invalidLot = Guid.NewGuid();

        var result = await PushAsync(
            test,
            tenant,
            Operation(
                Guid.NewGuid(),
                inventoryId,
                tenant,
                "fingerprint-rollback-001",
                new[]
                {
                    Line(
                        Guid.NewGuid(),
                        productA.GlobalId,
                        validLot,
                        5,
                        1000L),
                    Line(
                        Guid.NewGuid(),
                        productB.GlobalId,
                        invalidLot,
                        0,
                        1000L)
                }));

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.ValidationFailed, result.ErrorCode);

        Assert.Empty(test.Db.InitialInventories);
        Assert.Empty(test.Db.InitialInventoryLines);
        Assert.Empty(test.Db.InventoryLots);
        Assert.Empty(test.Db.InventoryMovements);
        Assert.Empty(test.Db.InboundOperations);
        Assert.DoesNotContain(
            test.Db.SyncChanges,
            x => x.EntityGlobalId == inventoryId);
    }

    private static async Task<Product> AddProductAsync(
        TestDatabase test,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        string code)
    {
        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = code,
            Name = $"Product {code}",
            SalePriceCents = 14000L,
            Active = true,
            UpdatedAt = DateTimeOffset.UtcNow,
            ServerVersion = 1
        };

        test.Db.Products.Add(product);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return product;
    }

    private static async Task<UserAccount> AddUserAsync(
        TestDatabase test,
        Business business,
        string role,
        string name)
    {
        var now = DateTimeOffset.UtcNow;

        var user = new UserAccount
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = business.Id,
            Name = name,
            Username = $"user-{Guid.NewGuid():N}",
            PasswordHash = "hash",
            PasswordSalt = "salt",
            Role = role,
            Active = true,
            CreatedAt = now,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Users.Add(user);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return user;
    }

    private static object Line(
        Guid lineId,
        Guid productId,
        Guid lotId,
        int quantity,
        long unitCostCents) =>
        new
        {
            globalId = lineId,
            productGlobalId = productId,
            lotGlobalId = lotId,
            quantity,
            unitCostCents
        };

    private static SyncOperationDto Operation(
        Guid operationId,
        Guid inventoryId,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        string fingerprint,
        object[] lines,
        Guid? userGlobalId = null)
    {
        using var document = JsonDocument.Parse(
            JsonSerializer.Serialize(new
            {
                globalId = inventoryId,
                businessGlobalId = tenant.Business.GlobalId,
                branchGlobalId = tenant.Branch.GlobalId,
                deviceGlobalId = tenant.Device.GlobalId,
                userGlobalId = userGlobalId ?? tenant.User.GlobalId,
                sourceFingerprint = fingerprint,
                sourceName = "initial_inventory.csv",
                createdAt = DateTimeOffset.UtcNow,
                lines
            }));

        return new SyncOperationDto(
            operationId,
            "InitialInventory",
            inventoryId,
            "Create",
            1,
            document.RootElement.Clone());
    }

    private static async Task<SyncOperationResult> PushAsync(
        TestDatabase test,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        SyncOperationDto operation)
    {
        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        return Assert.Single(response.Results);
    }

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
}