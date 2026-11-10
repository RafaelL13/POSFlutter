using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// Read-only tenant-scoped administrative transfer history.
[Route("admin/inventory/transfers")]
public sealed class AdminInventoryTransfersController(PosDbContext db) : Controller
{
    [HttpGet("")]
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.Ordinal))
            return StatusCode(403);

        var active = await db.Businesses.AsNoTracking().AnyAsync(x =>
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
        if (!active) return StatusCode(403);

        var rows = await db.CentralInventoryTransferReceipts.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId)
            .OrderByDescending(x => x.ReceivedAt)
            .ThenByDescending(x => x.Id)
            .Take(100)
            .Select(x => new { x.TransferGlobalId, x.ReceivedAt })
            .ToListAsync(ct);
        return Json(new { readOnly = true, items = rows });
    }
}