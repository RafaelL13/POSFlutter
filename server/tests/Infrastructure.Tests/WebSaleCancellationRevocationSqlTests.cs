using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;
using Xunit;

namespace Pos.Infrastructure.Tests;

public sealed class WebSaleCancellationRevocationSqlTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Revoked_user_or_device_cannot_cancel_cash_sale(bool revokeDevice)
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CANREVOKE");
        var now = DateTimeOffset.UtcNow;
        var ct = TestContext.Current.CancellationToken;

        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = "R" + Guid.NewGuid().ToString("N"),
            Name = "Revocation test",
            SalePriceCents = 100,
            Active = true,
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
            Active = true,
            CreatedAt = now
        };

        var cash = new CashSession
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            DeviceId = tenant.Device.Id,
            UserId = tenant.User.Id,
            OpenedAt = now,
            Status = "Open",
            UpdatedAt = now
        };

        test.Db.AddRange(product, lot, cash);
        await test.Db.SaveChangesAsync(ct);

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
            tenant.Device.Mode
        );

        var sale = await new WebCheckoutService(test.Db).CheckoutAsync(
            new WebCheckoutRequest(
                Guid.NewGuid(),
                [new WebCheckoutLine(product.GlobalId, 2)],
                [new WebCheckoutPayment("Cash", 200)],
                200
            ),
            context,
            ct
        );

        test.Db.ChangeTracker.Clear();

        if (revokeDevice)
        {
            var device = await test.Db.Devices.SingleAsync(
                x => x.Id == tenant.Device.Id, ct);
            device.Active = false;
        }
        else
        {
            var user = await test.Db.Users.SingleAsync(
                x => x.Id == tenant.User.Id, ct);
            user.Active = false;
        }

        await test.Db.SaveChangesAsync(ct);
        test.Db.ChangeTracker.Clear();

        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => new WebSaleCancellationService(test.Db).CancelAsync(
                new WebSaleCancellationRequest(
                    sale.SaleGlobalId,
                    "Revoked identity test"
                ),
                context,
                ct
            )
        );

        test.Db.ChangeTracker.Clear();

        var persistedSale = await test.Db.Sales.SingleAsync(
            x => x.GlobalId == sale.SaleGlobalId, ct);

        Assert.Equal("Confirmed", persistedSale.Status);

        Assert.Equal(
            3,
            (await test.Db.InventoryLots.SingleAsync(ct)).AvailableQuantity
        );

        Assert.Empty(await test.Db.InventoryMovements
            .Where(x => x.Type == "Cancellation"
                && x.ReferenceGlobalId == sale.SaleGlobalId)
            .ToListAsync(ct));

        Assert.Empty(await test.Db.CashMovements
            .Where(x => x.Type == "ManualOut")
            .ToListAsync(ct));

        Assert.Empty(await test.Db.SyncChanges
            .Where(x => x.EntityGlobalId == sale.SaleGlobalId
                && x.Operation == "Cancel")
            .ToListAsync(ct));
    }
}