using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Pos.Domain;
using Pos.Infrastructure;
using PosFlutter.Web.Controllers;
using PosFlutter.Web.Services;

namespace Pos.Infrastructure.Tests;

/// <summary>
/// SQL Server-only tests for the R9 adjustment commit endpoint.  The fixture
/// creates a uniquely named disposable database; no shared LAB database is
/// used or altered by these tests.
/// </summary>
public sealed class AdminInventoryAdjustmentsSqlIntegrationTests
{
    private const int Port = 59446;

    private static AdminInventoryAdjustmentsController Controller(
        CategorySqlTestDatabase fixture, ISession session, bool allow = true)
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AdminCatalog:AllowLabWrites"] = allow ? "true" : "false",
            ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName,
            ["AdminCatalog:LabPort"] = Port.ToString()
        }).Build();
        var http = new DefaultHttpContext();
        http.Request.Host = new HostString("localhost", Port);
        http.Session = session;
        var controller = new AdminInventoryAdjustmentsController(fixture.CreateDbContext());
        controller.ControllerContext = new ControllerContext(new ActionContext(
            http, new RouteData(), new Microsoft.AspNetCore.Mvc.Controllers.ControllerActionDescriptor()));
        return controller;
    }

    private static async Task<Product> SeedProductAsync(CategorySqlTestDatabase fixture,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant, string code = "ADJ-001")
    {
        var product = new Product
        {
            GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id, Code = code,
            Name = code, Presentation = "Piece", SalePriceCents = 1000,
            MinimumStock = 0, Active = true, UpdatedAt = DateTimeOffset.UtcNow
        };
        await using var db = fixture.CreateDbContext();
        db.Products.Add(product);
        await db.SaveChangesAsync();
        return product;
    }

    private static async Task SeedLotAsync(CategorySqlTestDatabase fixture,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        Product product, int quantity, long unitCostCents, DateTimeOffset entryDate)
    {
        await using var db = fixture.CreateDbContext();
        db.InventoryLots.Add(new InventoryLot
        {
            GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id, BranchId = tenant.Branch.Id,
            ProductGlobalId = product.GlobalId, EntryDate = entryDate, CreatedAt = entryDate,
            InitialQuantity = quantity, AvailableQuantity = quantity, UnitCostCents = unitCostCents, Active = true
        });
        await db.SaveChangesAsync();
    }

    private static MemoryTestSession Session((Business Business, Branch Branch, Device Device, UserAccount User) tenant)
    {
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(tenant));
        return session;
    }

    private static AdminInventoryAdjustmentCommitRequest Request(Guid productId, int delta, Guid? key = null, long? cost = null,
        string reason = "Verified inventory adjustment") =>
        new(productId, delta, reason, key ?? Guid.NewGuid(), cost);

    [Fact]
    public async Task Adjustment_in_out_uses_fifo_and_replay_is_exactly_once()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var tenant = await fixture.SeedTenantAsync("AdjustmentA");
        var product = await SeedProductAsync(fixture, tenant);
        var start = DateTimeOffset.UtcNow.AddMinutes(-10);
        await SeedLotAsync(fixture, tenant, product, 3, 110, start);
        await SeedLotAsync(fixture, tenant, product, 4, 220, start.AddMinutes(1));
        var session = Session(tenant);
        var key = Guid.NewGuid();
        var input = Request(product.GlobalId, 5, key, 0, "Stock correction received");
        var writer = Controller(fixture, session);
        try
        {
            Assert.IsType<OkObjectResult>(await writer.Commit(input, new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
            {
                ["AdminCatalog:AllowLabWrites"] = "true", ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName, ["AdminCatalog:LabPort"] = Port.ToString()
            }).Build(), CancellationToken.None));
        }
        finally { await writer.DisposeDbAsync(); }

        var outKey = Guid.NewGuid();
        var output = Request(product.GlobalId, -5, outKey, null, "Stock correction issued");
        var outWriter = Controller(fixture, session);
        try
        {
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
            {
                ["AdminCatalog:AllowLabWrites"] = "true", ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName, ["AdminCatalog:LabPort"] = Port.ToString()
            }).Build();
            Assert.IsType<OkObjectResult>(await outWriter.Commit(output, config, CancellationToken.None));
            Assert.IsType<OkObjectResult>(await outWriter.Commit(output, config, CancellationToken.None));
        }
        finally { await outWriter.DisposeDbAsync(); }

        await using var verify = fixture.CreateDbContext();
        var lots = await verify.InventoryLots.Where(x => x.BusinessId == tenant.Business.Id && x.ProductGlobalId == product.GlobalId)
            .OrderBy(x => x.EntryDate).ThenBy(x => x.Id).ToListAsync();
        Assert.Equal(new[] { 0, 2, 5 }, lots.Select(x => x.AvailableQuantity));
        Assert.Equal(2, await verify.InventoryMovements.CountAsync(x => x.ReferenceGlobalId == key || x.ReferenceGlobalId == outKey));
        Assert.Equal(-5, (await verify.InventoryMovements.SingleAsync(x => x.ReferenceGlobalId == outKey)).QuantityDelta);
    }

    [Fact]
    public async Task Insufficient_conflict_invalid_request_and_cross_tenant_attempt_leave_no_writes()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var a = await fixture.SeedTenantAsync("AdjustmentA");
        var b = await fixture.SeedTenantAsync("AdjustmentB");
        var product = await SeedProductAsync(fixture, a);
        await SeedLotAsync(fixture, a, product, 2, 100, DateTimeOffset.UtcNow.AddMinutes(-1));
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
        {
            ["AdminCatalog:AllowLabWrites"] = "true", ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName, ["AdminCatalog:LabPort"] = Port.ToString()
        }).Build();
        var aWriter = Controller(fixture, Session(a));
        try { Assert.IsType<ConflictObjectResult>(await aWriter.Commit(Request(product.GlobalId, -3, reason: "Insufficient stock test"), config, CancellationToken.None)); }
        finally { await aWriter.DisposeDbAsync(); }
        var bWriter = Controller(fixture, Session(b));
        try { Assert.IsType<NotFoundObjectResult>(await bWriter.Commit(Request(product.GlobalId, 1, cost: 100, reason: "Cross tenant product test"), config, CancellationToken.None)); }
        finally { await bWriter.DisposeDbAsync(); }
        var invalid = Controller(fixture, Session(a));
        try { Assert.IsType<BadRequestObjectResult>(await invalid.Commit(Request(product.GlobalId, 1, cost: null, reason: "Invalid cost test"), config, CancellationToken.None)); }
        finally { await invalid.DisposeDbAsync(); }
        await using var verify = fixture.CreateDbContext();
        Assert.Equal(2, await verify.InventoryLots.Where(x => x.ProductGlobalId == product.GlobalId).SumAsync(x => x.AvailableQuantity));
        Assert.Equal(0, await verify.InventoryMovements.CountAsync());
    }

    [Fact]
    public async Task Concurrent_same_idempotency_key_creates_one_movement_and_payload_conflict_is_rejected()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var tenant = await fixture.SeedTenantAsync("AdjustmentConcurrent");
        var product = await SeedProductAsync(fixture, tenant);
        var key = Guid.NewGuid();
        var request = Request(product.GlobalId, 7, key, 333, "Concurrent adjustment test");
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
        {
            ["AdminCatalog:AllowLabWrites"] = "true", ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName, ["AdminCatalog:LabPort"] = Port.ToString()
        }).Build();
        async Task<IActionResult> InvokeAsync()
        {
            var controller = Controller(fixture, Session(tenant));
            try { return await controller.Commit(request, config, CancellationToken.None); }
            finally { await controller.DisposeDbAsync(); }
        }
        var results = await Task.WhenAll(InvokeAsync(), InvokeAsync());
        Assert.All(results, result => Assert.IsType<OkObjectResult>(result));
        var conflictController = Controller(fixture, Session(tenant));
        try
        {
            Assert.IsType<ConflictObjectResult>(await conflictController.Commit(
                Request(product.GlobalId, 8, key, 333, "Concurrent adjustment test"), config, CancellationToken.None));
        }
        finally { await conflictController.DisposeDbAsync(); }
        await using var verify = fixture.CreateDbContext();
        Assert.Equal(1, await verify.InventoryMovements.CountAsync(x => x.ReferenceGlobalId == key));
        Assert.Equal(7, await verify.InventoryLots.Where(x => x.ProductGlobalId == product.GlobalId).SumAsync(x => x.AvailableQuantity));
    }

    [Fact]
    public async Task Commit_requires_admin_active_context_and_antiforgery_contract()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var admin = await fixture.SeedTenantAsync("AdjustmentAdmin");
        var viewer = await fixture.SeedTenantAsync("AdjustmentViewer", "Viewer");
        var product = await SeedProductAsync(fixture, admin);
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
        {
            ["AdminCatalog:AllowLabWrites"] = "true", ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName, ["AdminCatalog:LabPort"] = Port.ToString()
        }).Build();
        var noSession = Controller(fixture, new MemoryTestSession());
        try { Assert.IsType<UnauthorizedResult>(await noSession.Commit(Request(product.GlobalId, 1, cost: 100), config, CancellationToken.None)); }
        finally { await noSession.DisposeDbAsync(); }
        var viewerController = Controller(fixture, Session(viewer));
        try { Assert.Equal(403, Assert.IsType<StatusCodeResult>(await viewerController.Commit(Request(product.GlobalId, 1, cost: 100), config, CancellationToken.None)).StatusCode); }
        finally { await viewerController.DisposeDbAsync(); }
        var method = typeof(AdminInventoryAdjustmentsController).GetMethod("Commit")!;
        Assert.NotNull(Attribute.GetCustomAttribute(method, typeof(ValidateAntiForgeryTokenAttribute)));
        await using var verify = fixture.CreateDbContext();
        Assert.Equal(0, await verify.InventoryMovements.CountAsync());
    }

    [Fact]
    public async Task Sql_server_schema_has_the_durable_filtered_adjustment_idempotency_index()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var connection = fixture.Db.Database.GetDbConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT COUNT_BIG(*)
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.InventoryMovements')
              AND name = N'IX_InventoryMovements_BusinessId_BranchId_ReferenceGlobalId'
              AND is_unique = 1
              AND filter_definition LIKE N'%AdjustmentIn%'
              AND filter_definition LIKE N'%AdjustmentOut%';
            """;
        Assert.Equal(1L, Convert.ToInt64(await command.ExecuteScalarAsync()));
    }
}

internal static class InventoryAdjustmentControllerCleanup
{
    public static async Task DisposeDbAsync(this AdminInventoryAdjustmentsController controller)
    {
        var field = typeof(AdminInventoryAdjustmentsController)
            .GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            .FirstOrDefault(x => typeof(PosDbContext).IsAssignableFrom(x.FieldType));
        if (field?.GetValue(controller) is PosDbContext db)
            await db.DisposeAsync();
    }
}
