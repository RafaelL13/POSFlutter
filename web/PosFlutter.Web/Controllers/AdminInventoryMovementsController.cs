using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// Read-only inventory ledger. Never changes lots, movements or stock.
[Route("admin/inventory/movements")]
public sealed class AdminInventoryMovementsController(PosDbContext db) : Controller
{
    [HttpGet("")]
    public IActionResult Index()
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        return View();
    }

    [HttpGet("data")]
    public async Task<IActionResult> Data([FromQuery] Guid? productGlobalId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal)) return StatusCode(403);
        if (page < 1 || pageSize is < 1 or > 100) return BadRequest(new { code = "INVALID_PAGING" });
        if (productGlobalId == Guid.Empty) return BadRequest(new { code = "INVALID_PRODUCT" });
        if ((long)(page - 1) * pageSize > int.MaxValue) return BadRequest(new { code = "PAGE_OUT_OF_RANGE" });

        var actorActive = await db.Users.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
            x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct);
        var businessActive = await db.Businesses.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct);
        var branchActive = await db.Branches.AsNoTracking().AnyAsync(x =>
            x.Id == tenant.BranchId && x.BusinessId == tenant.BusinessId &&
            x.GlobalId == tenant.BranchGlobalId && x.Active, ct);
        if (!actorActive || !businessActive || !branchActive) return StatusCode(403);

        if (productGlobalId.HasValue && !await db.Products.AsNoTracking().AnyAsync(x =>
                x.BusinessId == tenant.BusinessId && x.GlobalId == productGlobalId.Value, ct))
            return NotFound(new { code = "PRODUCT_NOT_FOUND" });

        var query = db.InventoryMovements.AsNoTracking().Where(x =>
            x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId);
        if (productGlobalId.HasValue)
            query = query.Where(x => x.ProductGlobalId == productGlobalId.Value);

        var items = await query.OrderByDescending(x => x.MovementDate).ThenByDescending(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new
            {
                x.GlobalId, x.ProductGlobalId, x.MovementDate, x.Type,
                x.QuantityDelta, x.PreviousStock, x.NewStock,
                x.ReferenceGlobalId, x.Notes
            }).ToListAsync(ct);
        return Ok(new { page, pageSize, items, hasMore = items.Count == pageSize });
    }
}
