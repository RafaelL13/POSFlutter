using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class InitialInventorySaleE2ETests
{
    [Fact]
    public async Task Initial_inventory_then_sale_preserves_fifo_cost_profit_and_idempotency()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync(
            "P003-E2E",
            role: "Manager");

        var now = DateTimeOffset.UtcNow;

        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "P001",
            Name = "Producto P001",
            Presentation = "Pieza",
            SalePriceCents = 14000L,
            MinimumStock = 0,
            Active = true,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Products.Add(product);
        await test.Db.SaveChangesAsync(
            TestContext.Current.CancellationToken);

        var inventoryOperationId = Guid.NewGuid();
        var inventoryId = Guid.NewGuid();
        var inventoryLineId = Guid.NewGuid();
        var lotId = Guid.NewGuid();
        const string fingerprint = "p003-p001-10x10000";

        using var inventoryDocument = JsonDocument.Parse(
            JsonSerializer.Serialize(new
            {
                globalId = inventoryId,
                businessGlobalId = tenant.Business.GlobalId,
                branchGlobalId = tenant.Branch.GlobalId,
                deviceGlobalId = tenant.Device.GlobalId,
                userGlobalId = tenant.User.GlobalId,
                sourceFingerprint = fingerprint,
                sourceName = "P003.csv",
                createdAt = now,
                lines = new[]
                {
                    new
                    {
                        globalId = inventoryLineId,
                        productGlobalId = product.GlobalId,
                        lotGlobalId = lotId,
                        quantity = 10,
                        unitCostCents = 10000L
                    }
                }
            }));

        var inventoryOperation = new SyncOperationDto(
            inventoryOperationId,
            "InitialInventory",
            inventoryId,
            "Create",
            1,
            inventoryDocument.RootElement.Clone());

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

        var service = new SyncService(test.Db);

        var inventoryPush = await service.PushAsync(
            new SyncPushRequest([inventoryOperation]),
            context,
            TestContext.Current.CancellationToken);

        var inventoryResult = Assert.Single(inventoryPush.Results);
        Assert.Equal("Applied", inventoryResult.Status);

        var initialLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lotId,
                TestContext.Current.CancellationToken);

        Assert.Equal(10, initialLot.InitialQuantity);
        Assert.Equal(10, initialLot.AvailableQuantity);
        Assert.Equal(10000L, initialLot.UnitCostCents);

        var initialMovement = await test.Db.InventoryMovements
            .SingleAsync(
                x =>
                    x.ReferenceGlobalId == inventoryId &&
                    x.Type == "InitialInventory",
                TestContext.Current.CancellationToken);

        Assert.Equal(10, initialMovement.QuantityDelta);
        Assert.Equal(0, initialMovement.PreviousStock);
        Assert.Equal(10, initialMovement.NewStock);

        var saleOperationId = Guid.NewGuid();
        var saleId = Guid.NewGuid();
        var saleIdempotencyKey = Guid.NewGuid();
        var saleLineId = Guid.NewGuid();
        var saleAllocationId = Guid.NewGuid();
        var paymentId = Guid.NewGuid();
        var saleDate = now.AddMinutes(1);

        using var saleDocument = JsonDocument.Parse(
            JsonSerializer.Serialize(new
            {
                globalId = saleId,
                idempotencyKey = saleIdempotencyKey,
                businessGlobalId = tenant.Business.GlobalId,
                branchGlobalId = tenant.Branch.GlobalId,
                deviceGlobalId = tenant.Device.GlobalId,
                userGlobalId = tenant.User.GlobalId,
                folio = "P003-001",
                saleDateTime = saleDate,

                subtotalCents = 42000L,
                discountCents = 0L,
                totalCents = 42000L,

                fifoCostCents = 30000L,
                grossProfitCents = 12000L,

                paymentMethod = "Cash",
                receivedCents = 42000L,
                changeCents = 0L,

                lines = new[]
                {
                    new
                    {
                        detailGlobalId = saleLineId,
                        productGlobalId = product.GlobalId,
                        quantity = 3,
                        unitPriceCents = 14000L,
                        totalCents = 42000L,
                        fifoCostCents = 30000L,
                        lots = new[]
                        {
                            new
                            {
                                globalId = saleAllocationId,
                                lotGlobalId = lotId,
                                inventoryLotGlobalId = lotId,
                                quantity = 3,
                                unitCostCents = 10000L,
                                totalCostCents = 30000L
                            }
                        }
                    }
                },

                payments = new[]
                {
                    new
                    {
                        globalId = paymentId,
                        method = "Cash",
                        amountCents = 42000L
                    }
                }
            }));

        var saleOperation = new SyncOperationDto(
            saleOperationId,
            "Sale",
            saleId,
            "Create",
            2,
            saleDocument.RootElement.Clone());

        var salePush = await service.PushAsync(
            new SyncPushRequest([saleOperation]),
            context,
            TestContext.Current.CancellationToken);

        var saleResult = Assert.Single(salePush.Results);
        Assert.Equal("Applied", saleResult.Status);

        var storedSale = await test.Db.Sales
            .Include(x => x.Lines)
            .ThenInclude(x => x.Lots)
            .Include(x => x.Payments)
            .SingleAsync(
                x => x.GlobalId == saleId,
                TestContext.Current.CancellationToken);

        Assert.Equal(42000L, storedSale.SubtotalCents);
        Assert.Equal(42000L, storedSale.TotalCents);
        Assert.Equal(30000L, storedSale.FifoCostCents);
        Assert.Equal(12000L, storedSale.GrossProfitCents);
        Assert.Equal("Confirmed", storedSale.Status);

        var storedLine = Assert.Single(storedSale.Lines);
        Assert.Equal(3, storedLine.Quantity);
        Assert.Equal(14000L, storedLine.UnitPriceCents);
        Assert.Equal(42000L, storedLine.TotalCents);
        Assert.Equal(30000L, storedLine.FifoCostCents);

        var allocation = Assert.Single(storedLine.Lots);
        Assert.Equal(lotId, allocation.InventoryLotGlobalId);
        Assert.Equal(3, allocation.Quantity);
        Assert.Equal(10000L, allocation.UnitCostCents);
        Assert.Equal(30000L, allocation.TotalCostCents);

        var payment = Assert.Single(storedSale.Payments);
        Assert.Equal("Cash", payment.Method);
        Assert.Equal(42000L, payment.AmountCents);

        var remainingLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lotId,
                TestContext.Current.CancellationToken);

        Assert.Equal(10, remainingLot.InitialQuantity);
        Assert.Equal(7, remainingLot.AvailableQuantity);
        Assert.Equal(10000L, remainingLot.UnitCostCents);

        var saleMovement = await test.Db.InventoryMovements
            .SingleAsync(
                x =>
                    x.ReferenceGlobalId == saleId &&
                    x.Type == "Sale",
                TestContext.Current.CancellationToken);

        Assert.Equal(-3, saleMovement.QuantityDelta);
        Assert.Equal(10, saleMovement.PreviousStock);
        Assert.Equal(7, saleMovement.NewStock);

        var inventoryRetry = await service.PushAsync(
            new SyncPushRequest([inventoryOperation]),
            context,
            TestContext.Current.CancellationToken);

        Assert.Equal(
            "AlreadyProcessed",
            Assert.Single(inventoryRetry.Results).Status);

        var saleRetry = await service.PushAsync(
            new SyncPushRequest([saleOperation]),
            context,
            TestContext.Current.CancellationToken);

        Assert.Equal(
            "AlreadyProcessed",
            Assert.Single(saleRetry.Results).Status);

        Assert.Equal(
            1,
            await test.Db.InitialInventories.CountAsync(
                x => x.GlobalId == inventoryId,
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.InitialInventoryLines.CountAsync(
                x => x.InitialInventoryId ==
                    test.Db.InitialInventories
                        .Where(i => i.GlobalId == inventoryId)
                        .Select(i => i.Id)
                        .Single(),
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.InventoryLots.CountAsync(
                x => x.GlobalId == lotId,
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.Sales.CountAsync(
                x => x.GlobalId == saleId,
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.SaleLines.CountAsync(
                x => x.GlobalId == saleLineId,
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.SaleLotAllocations.CountAsync(
                x => x.GlobalId == saleAllocationId,
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1,
            await test.Db.SalePayments.CountAsync(
                x => x.GlobalId == paymentId,
                TestContext.Current.CancellationToken));

        var finalLot = await test.Db.InventoryLots
            .SingleAsync(
                x => x.GlobalId == lotId,
                TestContext.Current.CancellationToken);

        Assert.Equal(7, finalLot.AvailableQuantity);

        Assert.Equal(
            2,
            await test.Db.InboundOperations.CountAsync(
                TestContext.Current.CancellationToken));
    }
}