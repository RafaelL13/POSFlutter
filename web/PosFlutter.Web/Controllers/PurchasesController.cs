using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("purchases")]
public sealed class PurchasesController(PosDbContext db, PurchaseReceivingService receiving) : Controller
{
    // P054_V43_DIRECT_SQL_MVC: SQL queries use the same scoped PosDbContext as checkout.
    [HttpGet("")]
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return RedirectToAction("Login", "Home");
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase)) return StatusCode(403);
        var purchases = await db.Purchases.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId)
            .OrderByDescending(x => x.PurchaseDate).Take(200).ToListAsync(ct);
        var supplierIds = purchases.Select(x => x.SupplierGlobalId).Distinct().ToArray();
        ViewBag.SupplierNames = await db.Suppliers.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && supplierIds.Contains(x.GlobalId))
            .ToDictionaryAsync(x => x.GlobalId, x => x.Name, ct);
        return View(purchases);
    }

    [HttpGet("create")]
    public async Task<IActionResult> New(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return RedirectToAction("Login", "Home");
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase)) return StatusCode(403);
        ViewBag.Suppliers = await db.Suppliers.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.Active)
            .OrderBy(x => x.Name).Select(x => new Microsoft.AspNetCore.Mvc.Rendering.SelectListItem(x.Name, x.GlobalId.ToString())).ToListAsync(ct);
        ViewBag.Products = await db.Products.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.Active)
            .OrderBy(x => x.Name).Select(x => new Microsoft.AspNetCore.Mvc.Rendering.SelectListItem(x.Name, x.GlobalId.ToString())).ToListAsync(ct);
        ViewBag.PurchaseContext = new { businessGlobalId=tenant.BusinessGlobalId, branchGlobalId=tenant.BranchGlobalId, deviceGlobalId=tenant.DeviceGlobalId, userGlobalId=tenant.UserGlobalId };
        return View("Create");
    }

    [HttpGet("details/{id:guid}")]
    public async Task<IActionResult> Details(Guid id, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return RedirectToAction("Login", "Home");
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase)) return StatusCode(403);
        var purchase = await db.Purchases.AsNoTracking().Include(x => x.Lines).ThenInclude(x => x.Lot)
            .SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId && x.GlobalId == id, ct);
        if (purchase is null) return NotFound();
        return View(purchase);
    }
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create([FromBody] PurchaseSyncPayload? request, CancellationToken ct)
    {
        var tenant=WebTenantSession.Read(HttpContext.Session);
        if(tenant is null) return Unauthorized();
        if(request is null)
        {
            var errors = ModelState
                .Where(x => x.Value?.Errors.Count > 0)
                .Select(x => new {
                    Campo = x.Key,
                    CantidadErrores = x.Value!.Errors.Count
                }).ToArray();

            return BadRequest(new {
                message = "No se pudo interpretar el JSON de compra",
                errors
            });
        }
        if(!string.Equals(tenant.Role,"Administrator",StringComparison.OrdinalIgnoreCase)) return StatusCode(403);
        if(request.BusinessGlobalId!=tenant.BusinessGlobalId || request.BranchGlobalId!=tenant.BranchGlobalId || request.DeviceGlobalId!=tenant.DeviceGlobalId || request.UserGlobalId!=tenant.UserGlobalId) return BadRequest(new {message="Contexto de compra inválido"});
        await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        try {
            var prior=await db.Purchases.SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == request.GlobalId, ct);
            if(prior is not null) {
                // PURCHASE_REPLAY_PAYLOAD_GUARD_V36: never acknowledge a changed payload as a replay.
                var stored = await db.Purchases.AsNoTracking()
                    .Include(x => x.Lines).ThenInclude(x => x.Lot)
                    .SingleAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == request.GlobalId, ct);
                var sameHeader = stored.SupplierGlobalId == request.SupplierGlobalId
                    && stored.BranchId == tenant.BranchId
                    && stored.DeviceId == tenant.DeviceId
                    && stored.UserId == tenant.UserId
                    && stored.TotalCents == request.TotalCents
                    && stored.PurchaseDate == request.Date
                    && string.Equals(stored.Reference?.Trim(), request.Reference?.Trim(), StringComparison.Ordinal)
                    && string.Equals(stored.Notes?.Trim(), request.Notes?.Trim(), StringComparison.Ordinal);
                var sameLines = stored.Lines.Count == request.Lines.Count &&
                    request.Lines.All(r => stored.Lines.Count(x =>
                        x.GlobalId == r.DetailGlobalId &&
                        x.ProductGlobalId == r.ProductGlobalId &&
                        x.Quantity == r.Quantity &&
                        x.UnitCostCents == r.UnitCostCents &&
                        x.SubtotalCents == checked((long)r.Quantity * r.UnitCostCents) &&
                        x.Lot != null && x.Lot.GlobalId == r.LotGlobalId) == 1);
                if (!sameHeader || !sameLines)
                    return Conflict(new { message = "Purchase idempotency conflict: payload differs" });
                await tx.CommitAsync(ct);
                return Ok(new {globalId=prior.GlobalId,replay=true});
            }
            var purchase=await receiving.ReceiveAsync(request,tenant,ct);
            db.SyncChanges.Add(new Pos.Domain.SyncChange { BusinessId=tenant.BusinessId,EntityType="Purchase",EntityGlobalId=purchase.GlobalId,Operation="Create",Version=1,PayloadJson=JsonSerializer.Serialize(request, new JsonSerializerOptions(JsonSerializerDefaults.Web)),CreatedAt=DateTimeOffset.UtcNow });
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            return Ok(new {globalId=purchase.GlobalId,totalCents=purchase.TotalCents,replay=false});
        } catch(ArgumentException ex){return BadRequest(new {message=ex.Message});} catch(InvalidOperationException ex){return Conflict(new {message=ex.Message});}
    }
}
