using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class OfflineMultiUserSyncTests
{
    [Fact]
    public async Task Administrator_can_sync_sale_created_offline_by_seller_in_same_business()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("MULTI");
        var seller = await AddSellerAsync(test, tenant.Business);
        var (product, lot) = await SeedInventoryAsync(test, tenant);
        var saleId = Guid.NewGuid();

        var operation = SaleOperation(
            Guid.NewGuid(),
            saleId,
            tenant,
            seller.GlobalId,
            product,
            lot);

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);
        Assert.True(result.Status == "Applied", result.Error);

        var stored = await test.Db.Sales
            .SingleAsync(
                x => x.GlobalId == saleId,
                TestContext.Current.CancellationToken);

        Assert.Equal(seller.Id, stored.UserId);
        Assert.NotEqual(tenant.User.Id, stored.UserId);
        Assert.Equal(tenant.Business.Id, stored.BusinessId);

        var storedLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lot.GlobalId,
                TestContext.Current.CancellationToken);

        Assert.Equal(4, storedLot.AvailableQuantity);
        Assert.Single(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Authenticated_tenant_cannot_sync_sale_for_user_from_another_business()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenantA = await test.SeedTenantAsync("A");
        var tenantB = await test.SeedTenantAsync("B");
        var (product, lot) = await SeedInventoryAsync(test, tenantA);
        var saleId = Guid.NewGuid();

        var operation = SaleOperation(
            Guid.NewGuid(),
            saleId,
            tenantA,
            tenantB.User.GlobalId,
            product,
            lot);

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),
            Context(tenantA),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);

        Assert.NotEqual("Applied", result.Status);

        Assert.False(await test.Db.Sales.AnyAsync(
            x => x.GlobalId == saleId,
            TestContext.Current.CancellationToken));

        var storedLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lot.GlobalId,
                TestContext.Current.CancellationToken);

        Assert.Equal(5, storedLot.AvailableQuantity);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Administrator_can_sync_purchase_created_offline_by_seller_in_same_business()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("PURCHASE-ACTOR");
        var seller = await AddSellerAsync(test, tenant.Business);
        var inventory = await SeedInventoryAsync(test, tenant);
        var product = inventory.Product;

        var now = DateTimeOffset.UtcNow;
        var supplier = new Supplier
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Name = "Offline Supplier",
            Active = true,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Suppliers.Add(supplier);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);

        var purchaseId = Guid.NewGuid();
        var detailId = Guid.NewGuid();
        var lotId = Guid.NewGuid();
        var operationId = Guid.NewGuid();

        using var payload = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            globalId = purchaseId,
            businessGlobalId = tenant.Business.GlobalId,
            branchGlobalId = tenant.Branch.GlobalId,
            deviceGlobalId = tenant.Device.GlobalId,
            userGlobalId = seller.GlobalId,
            supplierGlobalId = supplier.GlobalId,
            date = now,
            reference = "OFFLINE-SELLER-PURCHASE",
            notes = "Historical seller purchase",
            totalCents = 150L,
            lines = new[]
            {
                new
                {
                    detailGlobalId = detailId,
                    productGlobalId = product.GlobalId,
                    quantity = 3,
                    unitCostCents = 50L,
                    subtotalCents = 150L,
                    lotGlobalId = lotId
                }
            }
        }));

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([
                new SyncOperationDto(
                    operationId,
                    "Purchase",
                    purchaseId,
                    "Create",
                    1,
                    payload.RootElement.Clone())
            ]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);
        Assert.True(result.Status == "Applied", result.Error);

        var storedPurchase = await test.Db.Purchases
            .SingleAsync(
                x => x.GlobalId == purchaseId,
                TestContext.Current.CancellationToken);

        Assert.Equal(seller.Id, storedPurchase.UserId);
        Assert.NotEqual(tenant.User.Id, storedPurchase.UserId);
        Assert.Equal(tenant.Business.Id, storedPurchase.BusinessId);
        Assert.Equal(tenant.Branch.Id, storedPurchase.BranchId);
        Assert.Equal(tenant.Device.Id, storedPurchase.DeviceId);
        Assert.Equal(supplier.GlobalId, storedPurchase.SupplierGlobalId);
        Assert.Equal(150L, storedPurchase.TotalCents);
        Assert.Equal("Confirmed", storedPurchase.Status);

        var storedLine = await test.Db.PurchaseLines
            .SingleAsync(
                x => x.GlobalId == detailId,
                TestContext.Current.CancellationToken);

        Assert.Equal(product.GlobalId, storedLine.ProductGlobalId);
        Assert.Equal(3, storedLine.Quantity);
        Assert.Equal(50L, storedLine.UnitCostCents);
        Assert.Equal(150L, storedLine.SubtotalCents);

        var storedLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lotId,
                TestContext.Current.CancellationToken);

        Assert.Equal(product.GlobalId, storedLot.ProductGlobalId);
        Assert.Equal(detailId, storedLot.PurchaseLineGlobalId);
        Assert.Equal(3, storedLot.InitialQuantity);
        Assert.Equal(3, storedLot.AvailableQuantity);
        Assert.Equal(50L, storedLot.UnitCostCents);
        Assert.True(storedLot.Active);

        var movement = await test.Db.InventoryMovements
            .SingleAsync(
                x => x.ReferenceGlobalId == purchaseId &&
                     x.ProductGlobalId == product.GlobalId,
                TestContext.Current.CancellationToken);

        Assert.Equal("Purchase", movement.Type);
        Assert.Equal(3, movement.QuantityDelta);
        Assert.Equal(5, movement.PreviousStock);
        Assert.Equal(8, movement.NewStock);
        Assert.Equal(seller.Id, movement.UserId);
        Assert.Equal(tenant.Device.Id, movement.DeviceId);

        var inbound = await test.Db.InboundOperations
            .SingleAsync(
                x => x.OperationGlobalId == operationId,
                TestContext.Current.CancellationToken);

        Assert.Equal(tenant.Business.Id, inbound.BusinessId);
        Assert.Equal("Purchase", inbound.EntityType);
        Assert.Equal(purchaseId, inbound.EntityGlobalId);
    }
    [Fact]
    public async Task Seller_actor_cannot_push_expense_even_when_transport_user_is_administrator()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("SELLER-DENIED");
        var seller = await AddSellerAsync(test, tenant.Business);
        var expenseId = Guid.NewGuid();

        using var payload = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            globalId = expenseId,
            businessGlobalId = tenant.Business.GlobalId,
            branchGlobalId = tenant.Branch.GlobalId,
            deviceGlobalId = tenant.Device.GlobalId,
            userGlobalId = seller.GlobalId,
            date = DateTimeOffset.UtcNow,
            concept = "Not allowed",
            category = "Security",
            amountCents = 100L,
            paymentMethod = "Cash",
            notes = (string?)null
        }));

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([
                new SyncOperationDto(
                    Guid.NewGuid(),
                    "Expense",
                    expenseId,
                    "Create",
                    1,
                    payload.RootElement.Clone())
            ]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.RoleDenied, result.ErrorCode);
        Assert.Empty(test.Db.Expenses);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Unknown_sale_actor_is_rejected_before_mutation()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("UNKNOWN-ACTOR");
        var inventory = await SeedInventoryAsync(test, tenant);
        var product = inventory.Product;
        var lot = inventory.Lot;
        var saleId = Guid.NewGuid();

        var operation = SaleOperation(
            Guid.NewGuid(),
            saleId,
            tenant,
            Guid.NewGuid(),
            product,
            lot);

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.RoleDenied, result.ErrorCode);

        Assert.False(await test.Db.Sales.AnyAsync(
            x => x.GlobalId == saleId,
            TestContext.Current.CancellationToken));

        Assert.Empty(test.Db.InboundOperations);
    }
    private static async Task<UserAccount> AddSellerAsync(
        TestDatabase test,
        Business business)
    {
        var now = DateTimeOffset.UtcNow;
        var password = PasswordHashing.Create("SellerPass123!");

        var seller = new UserAccount
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = business.Id,
            Name = "Offline Seller",
            Username = $"seller_{Guid.NewGuid():N}",
            PasswordHash = password.Hash,
            PasswordSalt = password.Salt,
            Role = "Seller",
            Active = true,
            CreatedAt = now,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Users.Add(seller);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return seller;
    }

    private static async Task<(Product Product, InventoryLot Lot)> SeedInventoryAsync(
        TestDatabase test,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant)
    {
        var now = DateTimeOffset.UtcNow;

        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = Guid.NewGuid().ToString("N"),
            Name = "Product",
            SalePriceCents = 100,
            UpdatedAt = now
        };

        var lot = new InventoryLot
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            ProductGlobalId = product.GlobalId,
            EntryDate = now,
            InitialQuantity = 5,
            AvailableQuantity = 5,
            UnitCostCents = 40,
            CreatedAt = now
        };

        test.Db.AddRange(product, lot);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return (product, lot);
    }

    private static SyncOperationDto SaleOperation(
        Guid operationId,
        Guid saleId,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        Guid historicalUserGlobalId,
        Product product,
        InventoryLot lot)
    {
        var payload = new
        {
            globalId = saleId,
            idempotencyKey = Guid.NewGuid(),
            businessGlobalId = tenant.Business.GlobalId,
            branchGlobalId = tenant.Branch.GlobalId,
            deviceGlobalId = tenant.Device.GlobalId,
            userGlobalId = historicalUserGlobalId,
            folio = Guid.NewGuid().ToString("N"),
            saleDateTime = DateTimeOffset.UtcNow,
            subtotalCents = 100L,
            discountCents = 0L,
            totalCents = 100L,
            fifoCostCents = 40L,
            grossProfitCents = 60L,
            paymentMethod = "Cash",
            receivedCents = 100L,
            changeCents = 0L,
            payments = new[]
            {
                new
                {
                    globalId = Guid.NewGuid(),
                    method = "Cash",
                    amountCents = 100L
                }
            },
            lines = new[]
            {
                new
                {
                    detailGlobalId = Guid.NewGuid(),
                    productGlobalId = product.GlobalId,
                    quantity = 1,
                    unitPriceCents = 100L,
                    totalCents = 100L,
                    fifoCostCents = 40L,
                    lots = new[]
                    {
                        new
                        {
                            globalId = Guid.NewGuid(),
                            lotGlobalId = lot.GlobalId,
                            quantity = 1,
                            unitCostCents = 40L,
                            totalCostCents = 40L
                        }
                    }
                }
            }
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(payload));

        return new SyncOperationDto(
            operationId,
            "Sale",
            saleId,
            "Create",
            2,
            document.RootElement.Clone());
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
