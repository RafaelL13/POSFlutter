using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.EntityFrameworkCore;
using PosFlutter.Web.Controllers;
using PosFlutter.Web.Services;

namespace Pos.Infrastructure.Tests;

public sealed class AdminProductsSqlIntegrationTests
{
    private const int Port = 59445;
    private static AdminProductsController Controller(CategorySqlTestDatabase fixture, ISession session, bool allow = true)
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
        {
            ["AdminCatalog:AllowLabWrites"] = allow ? "true" : "false",
            ["AdminCatalog:LabDatabaseName"] = fixture.DatabaseName,
            ["AdminCatalog:LabPort"] = Port.ToString()
        }).Build();
        var http = new DefaultHttpContext();
        http.Request.Host = new HostString("localhost", Port);
        http.Session = session;
        var controller = new AdminProductsController(fixture.CreateDbContext(), config, NullLogger<AdminProductsController>.Instance);
        controller.ControllerContext = new ControllerContext(new ActionContext(http, new RouteData(), new Microsoft.AspNetCore.Mvc.Controllers.ControllerActionDescriptor()));
        return controller;
    }

    private static AdminProductSaveRequest Request(string code, Guid? id = null, long? version = null) =>
        new(id, version, null, code, null, "Product " + code, "Piece", 1200, 2, true);

    [Fact]
    public async Task Admin_create_update_duplicate_sync_and_audit_are_atomic()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var a = await fixture.SeedTenantAsync("ProductA");
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(a));
        var controller = Controller(fixture, session);
        try
        {
            var created = Assert.IsType<OkObjectResult>(await controller.Save(Request("SKU-TEST"), CancellationToken.None));
            using var createdJson = JsonDocument.Parse(JsonSerializer.Serialize(created.Value));
            var id = createdJson.RootElement.GetProperty("globalId").GetGuid();
            Assert.Equal(1, createdJson.RootElement.GetProperty("serverVersion").GetInt64());
            await using (var verify = fixture.CreateDbContext())
            {
                Assert.Equal(1, await verify.Products.CountAsync(x => x.BusinessId == a.Business.Id && x.GlobalId == id));
                Assert.Equal(1, await verify.SyncChanges.CountAsync(x => x.BusinessId == a.Business.Id && x.EntityGlobalId == id && x.EntityType == "Product"));
                Assert.Equal(1, await verify.AdminProductAudits.CountAsync(x => x.BusinessId == a.Business.Id && x.ProductGlobalId == id));
            }
            Assert.IsType<ConflictObjectResult>(await controller.Save(Request("SKU-TEST"), CancellationToken.None));
            Assert.IsType<ConflictObjectResult>(await controller.Save(Request("SKU-TEST", id, 99), CancellationToken.None));
            var updated = Assert.IsType<OkObjectResult>(await controller.Save(Request("SKU-TEST", id, 1), CancellationToken.None));
            using var updatedJson = JsonDocument.Parse(JsonSerializer.Serialize(updated.Value));
            Assert.Equal(2, updatedJson.RootElement.GetProperty("serverVersion").GetInt64());
            await using var final = fixture.CreateDbContext();
            Assert.Equal(1, await final.Products.CountAsync(x => x.BusinessId == a.Business.Id && x.GlobalId == id));
            Assert.Equal(2, await final.SyncChanges.CountAsync(x => x.EntityGlobalId == id && x.EntityType == "Product"));
            Assert.Equal(2, await final.AdminProductAudits.CountAsync(x => x.ProductGlobalId == id));
        }
        finally { await controller.DisposeDbAsync(); }
    }

    [Fact]
    public async Task Viewer_and_disabled_guard_cannot_write()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var viewer = await fixture.SeedTenantAsync("ProductViewer", "Viewer");
        var admin = await fixture.SeedTenantAsync("ProductAdmin");
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(viewer));
        var controller = Controller(fixture, session);
        try { Assert.Equal(403, Assert.IsType<StatusCodeResult>(await controller.Save(Request("BLOCKED"), CancellationToken.None)).StatusCode); }
        finally { await controller.DisposeDbAsync(); }
        var adminSession = new MemoryTestSession();
        WebTenantSession.Store(adminSession, CategorySqlTestDatabase.Tenant(admin));
        var locked = Controller(fixture, adminSession, false);
        try { Assert.Equal(423, Assert.IsType<ObjectResult>(await locked.Save(Request("BLOCKED"), CancellationToken.None)).StatusCode); }
        finally { await locked.DisposeDbAsync(); }
        await using var verify = fixture.CreateDbContext();
        Assert.Equal(0, await verify.Products.CountAsync());
    }

    [Fact]
    public async Task Tenant_catalog_is_isolated_and_anonymous_cannot_write()
    {
        await using var fixture = await CategorySqlTestDatabase.CreateAsync();
        var a = await fixture.SeedTenantAsync("ProductTenantA");
        var b = await fixture.SeedTenantAsync("ProductTenantB");
        var sessionA = new MemoryTestSession();
        WebTenantSession.Store(sessionA, CategorySqlTestDatabase.Tenant(a));
        var writer = Controller(fixture, sessionA);
        try { Assert.IsType<OkObjectResult>(await writer.Save(Request("ONLY-A"), CancellationToken.None)); }
        finally { await writer.DisposeDbAsync(); }
        var sessionB = new MemoryTestSession();
        WebTenantSession.Store(sessionB, CategorySqlTestDatabase.Tenant(b));
        var reader = Controller(fixture, sessionB);
        try { Assert.DoesNotContain("ONLY-A", JsonSerializer.Serialize(Assert.IsType<OkObjectResult>(await reader.Catalog(CancellationToken.None)).Value)); }
        finally { await reader.DisposeDbAsync(); }
        var anonymous = Controller(fixture, new MemoryTestSession());
        try { Assert.IsType<UnauthorizedResult>(await anonymous.Save(Request("NO-SESSION"), CancellationToken.None)); }
        finally { await anonymous.DisposeDbAsync(); }
    }

    [Fact]
    public void Save_has_antiforgery_attribute()
    {
        var method = typeof(AdminProductsController).GetMethod("Save")!;
        Assert.NotNull(Attribute.GetCustomAttribute(method, typeof(ValidateAntiForgeryTokenAttribute)));
    }
}

internal static class ProductControllerCleanup
{
    public static async Task DisposeDbAsync(this AdminProductsController controller)
    {
        var field = typeof(AdminProductsController)
            .GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            .FirstOrDefault(x => typeof(Pos.Infrastructure.PosDbContext).IsAssignableFrom(x.FieldType));
        if (field?.GetValue(controller) is Pos.Infrastructure.PosDbContext db) await db.DisposeAsync();
    }
}
