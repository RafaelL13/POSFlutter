using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// Categories use the same isolated-LAB guard as the catalog editor.  The
// operation emits the established Category pull payload so Android clients do
// not need a web-only contract.
[Route("admin/categories")]
public sealed class AdminCategoriesController(PosDbContext db, IConfiguration configuration) : Controller
{
    // LAB writes remain opt-in and bound to one explicitly named disposable database.
    // Without an explicit database and port, writes are denied.
    private bool CanWriteLab()
    {
        var allowedDatabase = configuration["AdminCatalog:LabDatabaseName"];
        var allowedPort = configuration.GetValue<int>("AdminCatalog:LabPort");
        var actualDatabase = db.Database.GetDbConnection().Database;
        return configuration.GetValue<bool>("AdminCatalog:AllowLabWrites") &&
            !string.IsNullOrWhiteSpace(allowedDatabase) &&
            allowedDatabase.StartsWith("POSFlutter_MvcLab_", StringComparison.OrdinalIgnoreCase) &&
            string.Equals(actualDatabase, allowedDatabase, StringComparison.OrdinalIgnoreCase) &&
            allowedPort is > 1024 and <= 65535 &&
            string.Equals(HttpContext.Request.Host.Host, "localhost", StringComparison.OrdinalIgnoreCase) &&
            HttpContext.Request.Host.Port == allowedPort;
    }

    [HttpGet("")]
    public IActionResult Index()
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        ViewData["CanWriteLab"] = CanWriteLab();
        return View();
    }

    [HttpGet("list")]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        var rows = await db.Categories.AsNoTracking().Where(x => x.BusinessId == tenant.BusinessId)
            .OrderBy(x => x.Name).Select(x => new { x.GlobalId, x.Name, x.Description, x.Active, x.ServerVersion })
            .ToListAsync(ct);
        return Ok(rows);
    }

    [HttpPost("save")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Save([FromBody] AdminCategorySaveRequest? request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        if (!CanWriteLab()) return StatusCode(423, new { code = "LAB_WRITES_DISABLED" });
        if (request is null) return BadRequest(new { code = "INVALID_BODY" });
        var name = (request.Name ?? string.Empty).Trim();
        var description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
        if (name.Length is < 1 or > 160 || description is { Length: > 500 })
            return BadRequest(new { code = "INVALID_CATEGORY_VALUES" });

        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var actorActive = await db.Users.AsNoTracking().AnyAsync(x => x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId && x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct);
        var businessActive = await db.Businesses.AsNoTracking().AnyAsync(x => x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct);
        if (!actorActive || !businessActive) return StatusCode(403, new { code = "ADMIN_CONTEXT_INACTIVE" });
        if (await db.Categories.AsNoTracking().AnyAsync(x => x.BusinessId == tenant.BusinessId && x.Name == name, ct))
            return Conflict(new { code = "CATEGORY_NAME_ALREADY_EXISTS" });

        var now = DateTimeOffset.UtcNow;
        var category = new Category { GlobalId = Guid.NewGuid(), BusinessId = tenant.BusinessId, Name = name, Description = description, Active = true, UpdatedAt = now, ServerVersion = 1 };
        var payload = new CategoryPullPayload(category.GlobalId, tenant.BusinessGlobalId, category.Name, category.Description, category.Active, category.UpdatedAt, category.ServerVersion);
        db.Categories.Add(category);
        db.SyncChanges.Add(new SyncChange { BusinessId = tenant.BusinessId, EntityType = "Category", EntityGlobalId = category.GlobalId, Operation = "Create", Version = category.ServerVersion, PayloadJson = JsonSerializer.Serialize(payload, new JsonSerializerOptions(JsonSerializerDefaults.Web)), CreatedAt = now });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return Ok(new { globalId = category.GlobalId, serverVersion = category.ServerVersion, saved = true });
    }
}

public sealed record AdminCategorySaveRequest(string Name, string? Description);
