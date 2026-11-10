using PosFlutter.Web.Services;
using System;
using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;

namespace PosFlutter.Web.Controllers;

// LAB-only administrative catalog changes: disabled by default and pinned to an isolated database.
// Production requires a separate authorization, audit and central-source acceptance gate.
[Route("admin/products")]
public sealed class AdminProductsController(
    PosDbContext db,
    IConfiguration configuration,
    ILogger<AdminProductsController> logger) : Controller
{
    // Same explicit, fail-closed LAB gate already verified for Categories.
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
        return View("Index");
    }

    // Dedicated admin projection: /data/products intentionally omits CategoryGlobalId.
    // Editing through that limited projection would accidentally erase product categories.
    [HttpGet("catalog")]
    public async Task<IActionResult> Catalog(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        var activeActor = await db.Users.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
            x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct);
        var activeBusiness = await db.Businesses.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct);
        if (!activeActor || !activeBusiness) return StatusCode(403);
        var rows = await db.Products.AsNoTracking()
            .Where(p => p.BusinessId == tenant.BusinessId)
            .OrderBy(p => p.Name)
            .Select(p => new
            {
                p.GlobalId, p.CategoryGlobalId, p.Code, p.Barcode, p.Name,
                p.Presentation, p.SalePriceCents, p.MinimumStock,
                p.Active, p.ServerVersion,
                AvailableQuantity = db.InventoryLots.AsNoTracking()
                    .Where(l => l.BusinessId == tenant.BusinessId && l.BranchId == tenant.BranchId &&
                                l.Active && l.ProductGlobalId == p.GlobalId && l.AvailableQuantity > 0)
                    .Select(l => (int?)l.AvailableQuantity).Sum() ?? 0
            }).ToListAsync(ct);
        return Ok(rows);
    }

    // Audit history is administrator-only, tenant-scoped and limited to one product.
    [HttpGet("audit")]
    public async Task<IActionResult> Audit([FromQuery] Guid productGlobalId, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        if (productGlobalId == Guid.Empty)
            return BadRequest(new { code = "PRODUCT_ID_REQUIRED" });
        var activeActor = await db.Users.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
            x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct);
        var activeBusiness = await db.Businesses.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct);
        if (!activeActor || !activeBusiness) return StatusCode(403);
        // No cross-business leakage and no ability to request arbitrary audit history.
        if (!await db.Products.AsNoTracking().AnyAsync(x =>
            x.BusinessId == tenant.BusinessId && x.GlobalId == productGlobalId, ct))
            return NotFound(new { code = "PRODUCT_NOT_FOUND" });
        var rows = await db.AdminProductAudits.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.ProductGlobalId == productGlobalId)
            .OrderByDescending(x => x.Id)
            .Take(50)
            .Select(x => new
            {
                x.Id, x.ActorUserGlobalId, x.ActorDeviceId, x.BranchId,
                x.Operation, x.PreviousServerVersion, x.NewServerVersion,
                x.SyncChangeId, x.BeforeJson, x.AfterJson, x.CreatedAt
            }).ToListAsync(ct);
        return Ok(new { items = rows });
    }

    [HttpPost("save")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Save([FromBody] AdminProductSaveRequest? request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        if (!CanWriteLab()) return StatusCode(423, new { code = "LAB_WRITES_DISABLED" });
        if (request is null) return BadRequest(new { code = "INVALID_BODY" });

        var code = (request.Code ?? string.Empty).Trim();
        var name = (request.Name ?? string.Empty).Trim();
        var presentation = (request.Presentation ?? string.Empty).Trim();
        var barcode = string.IsNullOrWhiteSpace(request.Barcode) ? null : request.Barcode.Trim();
        if (code.Length is < 1 or > 80 ||
            name.Length is < 1 or > 160 ||
            presentation.Length is < 1 or > 80 ||
            barcode is { Length: > 120 } ||
            request.SalePriceCents < 0 ||
            request.MinimumStock < 0)
            return BadRequest(new { code = "INVALID_PRODUCT_VALUES" });

        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            // Revalidate the actor, business and device instead of trusting an old cookie alone.
            var activeActor = await db.Users.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct);
            var activeBusiness = await db.Businesses.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct);
            var activeBranch = await db.Branches.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BranchId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.BranchGlobalId && x.Active, ct);
            var activeDevice = await db.Devices.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.DeviceId && x.BranchId == tenant.BranchId &&
                x.GlobalId == tenant.DeviceGlobalId && x.Active && x.Mode == tenant.DeviceMode, ct);
            if (!activeActor || !activeBusiness || !activeBranch || !activeDevice)
                return StatusCode(403, new { code = "ADMIN_CONTEXT_INACTIVE" });

            if (request.CategoryGlobalId is { } categoryId &&
                !await db.Categories.AsNoTracking().AnyAsync(x =>
                    x.BusinessId == tenant.BusinessId && x.GlobalId == categoryId && x.Active, ct))
                return BadRequest(new { code = "CATEGORY_NOT_FOUND_IN_BUSINESS" });

            var creating = request.GlobalId is null || request.GlobalId == Guid.Empty;
            var id = creating ? Guid.NewGuid() : request.GlobalId!.Value;
            var duplicated = await db.Products.AsNoTracking().AnyAsync(x =>
                x.BusinessId == tenant.BusinessId && x.Code == code && x.GlobalId != id, ct);
            if (duplicated) return Conflict(new { code = "PRODUCT_CODE_ALREADY_EXISTS" });

            Product product;
            string? beforeJson = null;
            long? previousVersion = null;
            var now = DateTimeOffset.UtcNow;
            if (creating)
            {
                if (request.ExpectedServerVersion.HasValue)
                    return BadRequest(new { code = "UNEXPECTED_CREATE_VERSION" });
                product = new Product
                {
                    GlobalId = id,
                    BusinessId = tenant.BusinessId,
                    ServerVersion = 1
                };
                db.Products.Add(product);
            }
            else
            {
                product = await db.Products.SingleOrDefaultAsync(x =>
                    x.BusinessId == tenant.BusinessId && x.GlobalId == id, ct)
                    ?? throw new KeyNotFoundException("Product not found in tenant.");
                if (!request.ExpectedServerVersion.HasValue ||
                    product.ServerVersion != request.ExpectedServerVersion.Value)
                    return Conflict(new { code = "PRODUCT_VERSION_CONFLICT", currentServerVersion = product.ServerVersion });
                previousVersion = product.ServerVersion;
                beforeJson = JsonSerializer.Serialize(new ProductPullPayload(
                    product.GlobalId, tenant.BusinessGlobalId, product.CategoryGlobalId,
                    product.Code, product.Barcode, product.Name, product.Presentation,
                    product.SalePriceCents, product.MinimumStock, product.Active,
                    product.UpdatedAt, product.ServerVersion),
                    new JsonSerializerOptions(JsonSerializerDefaults.Web));
                checked { product.ServerVersion++; }
            }

            product.Code = code;
            product.Barcode = barcode;
            product.Name = name;
            product.Presentation = presentation;
            product.CategoryGlobalId = request.CategoryGlobalId;
            product.SalePriceCents = request.SalePriceCents;
            product.MinimumStock = request.MinimumStock;
            product.Active = request.Active;
            product.UpdatedAt = now;

            // Same pull payload/version channel already used by SyncService for products.
            var pull = new ProductPullPayload(
                product.GlobalId, tenant.BusinessGlobalId, product.CategoryGlobalId,
                product.Code, product.Barcode, product.Name, product.Presentation,
                product.SalePriceCents, product.MinimumStock, product.Active,
                product.UpdatedAt, product.ServerVersion);
            var syncChange = new SyncChange
            {
                BusinessId = tenant.BusinessId,
                EntityType = "Product",
                EntityGlobalId = product.GlobalId,
                Operation = creating ? "Create" : "Update",
                Version = product.ServerVersion,
                PayloadJson = JsonSerializer.Serialize(pull, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
                CreatedAt = now
            };
            db.SyncChanges.Add(syncChange);

            // First SaveChanges allocates the sync cursor; it is NOT committed yet.
            // The product and sync event MUST be rolled back if audit insertion fails.
            await db.SaveChangesAsync(ct);
            db.AdminProductAudits.Add(new AdminProductAudit
            {
                BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId,
                ActorUserId = tenant.UserId,
                ActorUserGlobalId = tenant.UserGlobalId,
                ActorDeviceId = tenant.DeviceId,
                ProductGlobalId = product.GlobalId,
                Operation = creating ? "Create" : "Update",
                PreviousServerVersion = previousVersion,
                NewServerVersion = product.ServerVersion,
                SyncChangeId = syncChange.Id,
                BeforeJson = beforeJson,
                AfterJson = JsonSerializer.Serialize(pull, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
                CreatedAt = now
            });
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            logger.LogInformation(
                "LAB admin catalog {Operation} actor={Actor} business={Business} product={Product} version={Version}",
                creating ? "Create" : "Update", tenant.UserGlobalId,
                tenant.BusinessGlobalId, product.GlobalId, product.ServerVersion);
            return Ok(new { globalId = product.GlobalId, serverVersion = product.ServerVersion, saved = true });
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { code = "PRODUCT_NOT_FOUND" });
        }
        catch (DbUpdateException ex)
        {
            logger.LogWarning(ex, "LAB admin catalog database conflict, actor={Actor}", tenant.UserGlobalId);
            return Conflict(new { code = "PRODUCT_SAVE_CONFLICT" });
        }
    }
}

public sealed record AdminProductSaveRequest(
    Guid? GlobalId,
    long? ExpectedServerVersion,
    Guid? CategoryGlobalId,
    string Code,
    string? Barcode,
    string Name,
    string Presentation,
    long SalePriceCents,
    int MinimumStock,
    bool Active);