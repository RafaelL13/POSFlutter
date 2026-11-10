using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// R9: read-only feasibility check paired with the guarded, transactional
// commit action in AdminInventoryAdjustmentsCommitController.cs.
[Route("admin/inventory/adjustments")]
public sealed partial class AdminInventoryAdjustmentsController(PosDbContext db) : Controller
{
    [HttpGet("preview")]
    public async Task<IActionResult> Preview([FromQuery] Guid productGlobalId,
        [FromQuery] int quantityDelta, [FromQuery] string? reason, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (tenant.Role != "Administrator") return StatusCode(403);
        if (productGlobalId == Guid.Empty || quantityDelta == 0 || quantityDelta == int.MinValue ||
            Math.Abs((long)quantityDelta) > 1000000 || string.IsNullOrWhiteSpace(reason) ||
            reason.Trim().Length is < 5 or > 240)
            return BadRequest(new { code = "INVALID_ADJUSTMENT_REQUEST" });

        var authorized = await db.Businesses.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct)
            && await db.Branches.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BranchId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.BranchGlobalId && x.Active, ct)
            && await db.Users.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct)
            && await db.Devices.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.DeviceId && x.BranchId == tenant.BranchId &&
                x.GlobalId == tenant.DeviceGlobalId && x.Active, ct);
        if (!authorized) return StatusCode(403);

        var product = await db.Products.AsNoTracking().Where(x =>
            x.BusinessId == tenant.BusinessId && x.GlobalId == productGlobalId && x.Active)
            .Select(x => new { x.GlobalId, x.Name }).SingleOrDefaultAsync(ct);
        if (product is null) return NotFound(new { code = "PRODUCT_NOT_FOUND" });

        var lots = await db.InventoryLots.AsNoTracking().Where(x =>
            x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
            x.ProductGlobalId == productGlobalId && x.Active)
            .OrderBy(x => x.EntryDate).ThenBy(x => x.Id)
            .Select(x => new { x.GlobalId, x.AvailableQuantity, x.InitialQuantity,
                x.UnitCostCents, x.EntryDate }).ToListAsync(ct);
        var available = lots.Sum(x => (long)x.AvailableQuantity);
        var feasible = quantityDelta > 0 || available >= -(long)quantityDelta;
        return Ok(new {
            readOnly = true, canCommit = false, product, quantityDelta,
            reason = reason.Trim(), currentStock = available,
            projectedStock = available + quantityDelta, feasible,
            code = feasible ? "PREVIEW_ONLY" : "INSUFFICIENT_STOCK",
            lots
        });
    }
}
