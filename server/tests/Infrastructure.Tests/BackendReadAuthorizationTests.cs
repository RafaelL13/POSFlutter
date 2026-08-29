using System.Text.Json;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

public sealed class BackendReadAuthorizationTests
{
    private static CancellationToken CancellationToken =>
        TestContext.Current.CancellationToken;

    [Fact]
    public void Policy_is_versioned_complete_and_fails_closed()
    {
        Assert.Equal(1, BackendReadAuthorization.AuthorizationPolicyVersion);
        foreach (var capability in Enum.GetValues<BackendReadCapability>())
        {
            Assert.NotEqual(
                BackendReadPermission.None,
                BackendReadAuthorization.PermissionFor(
                    "Administrator",
                    "PointOfSale",
                    capability));
            _ = BackendReadAuthorization.PermissionFor(
                "Manager",
                "PointOfSale",
                capability);
            _ = BackendReadAuthorization.PermissionFor(
                "Supervisor",
                "PointOfSale",
                capability);
            _ = BackendReadAuthorization.PermissionFor(
                "Seller",
                "PointOfSale",
                capability);
        }

        Assert.Equal(
            BackendReadPermission.None,
            BackendReadAuthorization.PermissionFor(
                "Unknown",
                "PointOfSale",
                BackendReadCapability.ProductsRead));
        Assert.Equal(
            BackendReadPermission.None,
            BackendReadAuthorization.PermissionFor(
                "Manager",
                "Unknown",
                BackendReadCapability.UsersRead));
    }

    [Fact]
    public async Task Seller_gets_only_own_operational_sales_and_cash()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Seller", role: "Seller");
        var data = await SeedSensitiveDataAsync(test, tenant);
        var service = new TenantReadService(test.Db);
        var context = Context(tenant);

        var sales = await service.SalesAsync(context, CancellationToken);
        Assert.Single(sales);
        Assert.Contains(data.OwnSaleGlobalId.ToString(), Json(sales));
        Assert.DoesNotContain(data.OtherSaleGlobalId.ToString(), Json(sales));
        Assert.Null(
            await service.SaleAsync(
                context,
                data.OtherSaleGlobalId,
                CancellationToken));
        AssertSafeOperational(Json(sales));

        var dashboard = Json(await service.DashboardAsync(context, CancellationToken));
        Assert.DoesNotContain("fifoCostCents", dashboard);
        Assert.DoesNotContain("grossProfitCents", dashboard);
        Assert.DoesNotContain("margin", dashboard, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("expensesCents", dashboard);

        var cash = await service.CashAsync(context, CancellationToken);
        Assert.Single(cash);
        Assert.Contains(data.OwnCashGlobalId.ToString(), Json(cash));
        Assert.DoesNotContain(data.OtherCashGlobalId.ToString(), Json(cash));
        Assert.DoesNotContain("differenceCents", Json(cash));
        Assert.DoesNotContain("888888", Json(cash));

        var inventory = Json(await service.InventoryAsync(context, CancellationToken));
        Assert.DoesNotContain("inventoryValueCents", inventory);
        Assert.DoesNotContain("777777", inventory);
    }

    [Fact]
    public async Task Seller_is_denied_sensitive_and_administrative_endpoints()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("SellerDeny", role: "Seller");
        await SeedSensitiveDataAsync(test, tenant);
        var service = new TenantReadService(test.Db);
        var context = Context(tenant);

        await Denied(() => service.PurchasesAsync(context, CancellationToken));
        await Denied(() => service.LotsAsync(context, CancellationToken));
        await Denied(() => service.ExpensesAsync(context, CancellationToken));
        await Denied(() => service.SuppliersAsync(context, CancellationToken));
        await Denied(() => service.UsersAsync(context, CancellationToken));
        await Denied(() => service.DevicesAsync(context, CancellationToken));
        await Denied(() => service.BusinessAsync(context, CancellationToken));
        await Denied(() => new RemoteReportService(test.Db).SummaryAsync(
            context,
            CurrentPeriod(),
            CancellationToken));
    }

    [Fact]
    public async Task Supervisor_gets_branch_operations_without_financial_leaks()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Supervisor", role: "Supervisor");
        await SeedSensitiveDataAsync(test, tenant);
        var service = new TenantReadService(test.Db);
        var context = Context(tenant);

        var sales = Json(await service.SalesAsync(context, CancellationToken));
        AssertSafeOperational(sales);
        var dashboard = Json(await service.DashboardAsync(context, CancellationToken));
        Assert.DoesNotContain("fifoCostCents", dashboard);
        Assert.DoesNotContain("grossProfitCents", dashboard);
        Assert.DoesNotContain("margin", dashboard, StringComparison.OrdinalIgnoreCase);

        var purchases = Json(await service.PurchasesAsync(context, CancellationToken));
        Assert.DoesNotContain("totalCents", purchases);
        Assert.DoesNotContain("444444", purchases);
        var lots = Json(await service.LotsAsync(context, CancellationToken));
        Assert.DoesNotContain("unitCostCents", lots);
        Assert.DoesNotContain("259259", lots);
        var inventory = Json(await service.InventoryAsync(context, CancellationToken));
        Assert.DoesNotContain("inventoryValueCents", inventory);
        Assert.DoesNotContain("777777", inventory);
        var cash = Json(await service.CashAsync(context, CancellationToken));
        Assert.DoesNotContain("differenceCents", cash);
        Assert.DoesNotContain("888888", cash);

        Assert.Contains(
            "333333",
            Json(await service.ExpensesAsync(context, CancellationToken)));
        await Denied(() => service.UsersAsync(context, CancellationToken));
        await Denied(() => service.DevicesAsync(context, CancellationToken));
    }

    [Theory]
    [InlineData("Manager")]
    [InlineData("Administrator")]
    public async Task Financial_roles_receive_authorized_fields(string role)
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync(role, role: role);
        await SeedSensitiveDataAsync(test, tenant);
        var service = new TenantReadService(test.Db);
        var context = Context(tenant);

        var dashboard = Json(await service.DashboardAsync(context, CancellationToken));
        Assert.Contains("fifoCostCents", dashboard);
        Assert.Contains("123466", dashboard);
        Assert.Contains("grossProfitCents", dashboard);
        Assert.Contains("654341", dashboard);
        Assert.Contains("marginBasisPoints", dashboard);
        Assert.Contains("inventoryValueCents", Json(
            await service.InventoryAsync(context, CancellationToken)));
        Assert.Contains("777777", Json(
            await service.InventoryAsync(context, CancellationToken)));
        Assert.Contains("444444", Json(
            await service.PurchasesAsync(context, CancellationToken)));
        Assert.Contains("259259", Json(
            await service.LotsAsync(context, CancellationToken)));
        Assert.Contains("888888", Json(
            await service.CashAsync(context, CancellationToken)));
        Assert.NotEmpty(await service.UsersAsync(context, CancellationToken));
        Assert.NotEmpty(await service.DevicesAsync(context, CancellationToken));
        Assert.NotNull(await service.BusinessAsync(context, CancellationToken));
        Assert.NotEmpty(await service.BranchesAsync(context, CancellationToken));

    }

    [Fact]
    public async Task Stale_role_inactive_user_and_cross_tenant_context_are_denied()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenantA = await test.SeedTenantAsync("Stale", role: "Seller");
        var tenantB = await test.SeedTenantAsync("Foreign", role: "Manager");
        var service = new TenantReadService(test.Db);

        await Denied(() => service.ProductsAsync(
            Context(tenantB, role: "Unsupported"),
            CancellationToken));

        tenantA.User.Role = "Manager";
        await test.Db.SaveChangesAsync(CancellationToken);
        await Denied(() => service.ProductsAsync(Context(tenantA, role: "Seller"), CancellationToken));

        tenantA.User.Active = false;
        await test.Db.SaveChangesAsync(CancellationToken);
        await Denied(() => service.ProductsAsync(Context(tenantA, role: "Manager"), CancellationToken));

        var mixed = new SyncTenantContext(
            tenantA.Business.Id,
            tenantA.Business.GlobalId,
            tenantA.Branch.Id,
            tenantA.Branch.GlobalId,
            tenantA.Device.Id,
            tenantA.Device.GlobalId,
            tenantB.User.Id,
            tenantB.User.GlobalId,
            tenantB.User.Role,
            tenantA.Device.Mode);
        await Denied(() => service.ProductsAsync(mixed, CancellationToken));
    }

    [Fact]
    public async Task AdminReadOnly_preserves_Manager_reads_without_elevation()
    {
        await using var test = await TestDatabase.CreateAsync();
        var manager = await test.SeedTenantAsync(
            "ManagerReadOnly",
            role: "Manager",
            mode: "AdminReadOnly");
        await SeedSensitiveDataAsync(test, manager);
        var service = new TenantReadService(test.Db);
        Assert.NotEmpty(await service.UsersAsync(Context(manager), CancellationToken));
        Assert.Contains(
            "fifoCostCents",
            Json(await service.DashboardAsync(Context(manager), CancellationToken)));

        await using var sellerTest = await TestDatabase.CreateAsync();
        var seller = await sellerTest.SeedTenantAsync(
            "SellerReadOnly",
            role: "Seller",
            mode: "AdminReadOnly");
        await SeedSensitiveDataAsync(sellerTest, seller);
        var sellerService = new TenantReadService(sellerTest.Db);
        await Denied(() => sellerService.UsersAsync(Context(seller), CancellationToken));
        AssertSafeOperational(Json(
            await sellerService.SalesAsync(Context(seller), CancellationToken)));
    }

    private static void AssertSafeOperational(string json)
    {
        Assert.DoesNotContain("fifoCostCents", json);
        Assert.DoesNotContain("grossProfitCents", json);
        Assert.DoesNotContain("123456", json);
        Assert.DoesNotContain("654321", json);
    }

    private static string Json(object value) =>
        JsonSerializer.Serialize(value, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private static Task Denied(Func<Task> operation) =>
        Assert.ThrowsAsync<UnauthorizedAccessException>(operation);

    private static Task Denied<T>(Func<Task<T>> operation) =>
        Assert.ThrowsAsync<UnauthorizedAccessException>(async () => await operation());

    private static ReportPeriod CurrentPeriod()
    {
        var now = DateTimeOffset.UtcNow;
        return new ReportPeriod(now.AddDays(-1), now.AddDays(1));
    }

    private static SyncTenantContext Context(
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        string? role = null) => new(
            tenant.Business.Id,
            tenant.Business.GlobalId,
            tenant.Branch.Id,
            tenant.Branch.GlobalId,
            tenant.Device.Id,
            tenant.Device.GlobalId,
            tenant.User.Id,
            tenant.User.GlobalId,
            role ?? tenant.User.Role,
            tenant.Device.Mode);

    private sealed record SensitiveData(
        Guid OwnSaleGlobalId,
        Guid OtherSaleGlobalId,
        Guid OwnCashGlobalId,
        Guid OtherCashGlobalId);

    private static async Task<SensitiveData> SeedSensitiveDataAsync(
        TestDatabase test,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant)
    {
        var now = DateTimeOffset.UtcNow;
        var secondUser = new UserAccount
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Name = "Second Seller",
            Username = $"seller-{Guid.NewGuid():N}",
            PasswordHash = "hash",
            PasswordSalt = "salt",
            Role = "Seller",
            CreatedAt = now,
            UpdatedAt = now
        };
        var supplier = new Supplier
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Name = "Sensitive Supplier",
            UpdatedAt = now
        };
        var product = new Product
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Code = $"P-{Guid.NewGuid():N}",
            Name = "Product",
            SalePriceCents = 1000000,
            UpdatedAt = now
        };
        test.Db.AddRange(secondUser, supplier, product);
        await test.Db.SaveChangesAsync(CancellationToken);

        var purchase = new Purchase
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            DeviceId = tenant.Device.Id,
            UserId = tenant.User.Id,
            SupplierGlobalId = supplier.GlobalId,
            PurchaseDate = now,
            TotalCents = 444444,
            CreatedAt = now
        };
        var lot = new InventoryLot
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            ProductGlobalId = product.GlobalId,
            EntryDate = now,
            InitialQuantity = 3,
            AvailableQuantity = 3,
            UnitCostCents = 259259,
            CreatedAt = now
        };
        var ownSale = Sale(
            tenant,
            tenant.User.Id,
            "OWN",
            1000000,
            123456,
            654321,
            now);
        var otherSale = Sale(
            tenant,
            secondUser.Id,
            "OTHER",
            5000,
            10,
            20,
            now);
        var expense = new Expense
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            DeviceId = tenant.Device.Id,
            UserId = tenant.User.Id,
            ExpenseDate = now,
            Concept = "Expense",
            AmountCents = 333333,
            CreatedAt = now
        };
        var ownCash = Cash(tenant, tenant.User.Id, 111111, now);
        var otherCash = Cash(tenant, secondUser.Id, 888888, now);
        test.Db.AddRange(purchase, lot, ownSale, otherSale, expense, ownCash, otherCash);
        await test.Db.SaveChangesAsync(CancellationToken);
        return new SensitiveData(
            ownSale.GlobalId,
            otherSale.GlobalId,
            ownCash.GlobalId,
            otherCash.GlobalId);
    }

    private static Sale Sale(
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        long userId,
        string folio,
        long total,
        long cost,
        long profit,
        DateTimeOffset now) => new()
        {
            GlobalId = Guid.NewGuid(),
            IdempotencyKey = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            DeviceId = tenant.Device.Id,
            UserId = userId,
            Folio = folio,
            SaleDateTime = now,
            SubtotalCents = total,
            TotalCents = total,
            FifoCostCents = cost,
            GrossProfitCents = profit,
            PaymentMethod = "Cash",
            Status = "Confirmed",
            CreatedAt = now
        };

    private static CashSession Cash(
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        long userId,
        long difference,
        DateTimeOffset now) => new()
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            BranchId = tenant.Branch.Id,
            DeviceId = tenant.Device.Id,
            UserId = userId,
            OpenedAt = now,
            OpeningBalanceCents = 100,
            Status = "Closed",
            CountedCashCents = 100,
            ExpectedCashCents = 100 - difference,
            DifferenceCents = difference,
            UpdatedAt = now
        };
}
