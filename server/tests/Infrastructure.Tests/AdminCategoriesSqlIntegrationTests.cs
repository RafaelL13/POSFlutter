using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using PosFlutter.Web.Controllers;
using PosFlutter.Web.Services;

namespace Pos.Infrastructure.Tests;

public sealed class AdminCategoriesSqlIntegrationTests
{
    private const int Port = 59445;
    private static readonly string[] ConfigKeys = { "AdminCatalog:AllowLabWrites", "AdminCatalog:LabDatabaseName", "AdminCatalog:LabPort" };

    private static AdminCategoriesController Controller(CategorySqlTestDatabase db, Microsoft.AspNetCore.Http.ISession session, bool allow = true)
    {
        var cfg = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            [ConfigKeys[0]] = allow ? "true" : "false",
            [ConfigKeys[1]] = db.DatabaseName,
            [ConfigKeys[2]] = Port.ToString()
        }).Build();
        var context = new DefaultHttpContext();
        context.Request.Host = new HostString("localhost", Port);
        context.Session = session;
        var controller = new AdminCategoriesController(db.CreateDbContext(), cfg);
        controller.ControllerContext = new ControllerContext(new ActionContext(context, new RouteData(), new Microsoft.AspNetCore.Mvc.Controllers.ControllerActionDescriptor()));
        return controller;
    }

    [Fact]
    public async Task Admin_creates_category_and_sync_event_and_cannot_duplicate()
    {
        await using var db = await CategorySqlTestDatabase.CreateAsync();
        var a = await db.SeedTenantAsync("A");
        var b = await db.SeedTenantAsync("B");
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(a));
        var c = Controller(db, session);
        try
        {
            var response = await c.Save(new AdminCategorySaveRequest("  IntegrationCategory  ", "Test"), CancellationToken.None);
            var ok = Assert.IsType<OkObjectResult>(response);
            using var json = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value));
            var id = json.RootElement.GetProperty("globalId").GetGuid();
            await using var verify = db.CreateDbContext();
            var category = await verify.Categories.SingleAsync(x => x.GlobalId == id);
            Assert.Equal(a.Business.Id, category.BusinessId);
            Assert.Equal("IntegrationCategory", category.Name);
            var evt = await verify.SyncChanges.SingleAsync(x => x.EntityGlobalId == id);
            Assert.Equal(a.Business.Id, evt.BusinessId);
            Assert.Equal("Category", evt.EntityType);
            Assert.Equal("Create", evt.Operation);
            Assert.Contains("IntegrationCategory", evt.PayloadJson);
            Assert.Equal(0, await verify.Categories.CountAsync(x => x.BusinessId == b.Business.Id));
            var duplicate = await c.Save(new AdminCategorySaveRequest("IntegrationCategory", "Test"), CancellationToken.None);
            Assert.IsType<ConflictObjectResult>(duplicate);
            Assert.Equal(1, await verify.Categories.CountAsync(x => x.GlobalId == id));
        }
        finally { await c.DisposeDbAsync(); }
    }

    [Fact]
    public async Task Viewer_and_disabled_guard_cannot_write()
    {
        await using var db = await CategorySqlTestDatabase.CreateAsync();
        var viewer = await db.SeedTenantAsync("Viewer", "Viewer");
        var admin = await db.SeedTenantAsync("Admin");
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(viewer));
        var c = Controller(db, session);
        try { Assert.Equal(403, Assert.IsType<StatusCodeResult>(await c.Save(new AdminCategorySaveRequest("Blocked", null), CancellationToken.None)).StatusCode); }
        finally { await c.DisposeDbAsync(); }
        var adminSession = new MemoryTestSession();
        WebTenantSession.Store(adminSession, CategorySqlTestDatabase.Tenant(admin));
        var locked = Controller(db, adminSession, false);
        try { Assert.Equal(423, Assert.IsType<ObjectResult>(await locked.Save(new AdminCategorySaveRequest("Blocked", null), CancellationToken.None)).StatusCode); }
        finally { await locked.DisposeDbAsync(); }
        await using var verify = db.CreateDbContext();
        Assert.Equal(0, await verify.Categories.CountAsync());
    }

    [Fact]
    public async Task Tenant_list_is_isolated_and_anonymous_is_rejected()
    {
        await using var db = await CategorySqlTestDatabase.CreateAsync();
        var a = await db.SeedTenantAsync("A");
        var b = await db.SeedTenantAsync("B");
        await using (var seed = db.CreateDbContext())
        {
            seed.Categories.Add(new Pos.Domain.Category { GlobalId = Guid.NewGuid(), BusinessId = a.Business.Id, Name = "OnlyA", UpdatedAt = DateTimeOffset.UtcNow, ServerVersion = 1 });
            await seed.SaveChangesAsync();
        }
        var session = new MemoryTestSession();
        WebTenantSession.Store(session, CategorySqlTestDatabase.Tenant(b));
        var c = Controller(db, session);
        try
        {
            var rows = Assert.IsType<OkObjectResult>(await c.List(CancellationToken.None));
            Assert.DoesNotContain("OnlyA", JsonSerializer.Serialize(rows.Value));
        }
        finally { await c.DisposeDbAsync(); }
        var anonymous = Controller(db, new MemoryTestSession());
        try { Assert.IsType<UnauthorizedResult>(await anonymous.Save(new AdminCategorySaveRequest("No", null), CancellationToken.None)); }
        finally { await anonymous.DisposeDbAsync(); }
    }

    [Fact]
    public void Save_requires_antiforgery_attribute()
    {
        var method = typeof(AdminCategoriesController).GetMethod("Save")!;
        Assert.NotNull(Attribute.GetCustomAttribute(method, typeof(ValidateAntiForgeryTokenAttribute)));
    }
}

internal static class CategoryControllerCleanup
{
    public static async Task DisposeDbAsync(this AdminCategoriesController controller)
    {
        // Controller owns a separate context created for each request in these tests.
        var field = typeof(AdminCategoriesController).GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            .FirstOrDefault(x => typeof(Pos.Infrastructure.PosDbContext).IsAssignableFrom(x.FieldType));
        if (field?.GetValue(controller) is Pos.Infrastructure.PosDbContext db) await db.DisposeAsync();
    }
}

internal sealed class MemoryTestSession : Microsoft.AspNetCore.Http.ISession
{
    private readonly Dictionary<string, byte[]> _values = new();
    public bool IsAvailable => true;
    public string Id { get; } = Guid.NewGuid().ToString();
    public IEnumerable<string> Keys => _values.Keys;
    public void Clear() => _values.Clear();
    public Task CommitAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
    public Task LoadAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
    public void Remove(string key) => _values.Remove(key);
    public void Set(string key, byte[] value) => _values[key] = value;
    public bool TryGetValue(string key, out byte[] value) => _values.TryGetValue(key, out value!);
}
