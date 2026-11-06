using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("checkout")]
public sealed class CheckoutController(WebCheckoutService checkout, PosDbContext db) : Controller
{
    [HttpPost]
    [RequestSizeLimit(32768)]
    public async Task<IActionResult> Create([FromBody] WebCheckoutRequest? request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Inicia sesión" });
        if (request is null) return BadRequest(new { message = "Checkout inválido" });
        try { return Ok(await checkout.CheckoutAsync(request, tenant, ct)); }
        catch (UnauthorizedAccessException) { HttpContext.Session.Clear(); return StatusCode(403, new { message = "Acceso denegado" }); }
        catch (ArgumentException) { return BadRequest(new { message = "Checkout inválido" }); }
        catch (InvalidOperationException) { return Conflict(new { message = "Stock insuficiente o conflicto" }); }
    }

    /* POSWEB_P04_STATUS_LOOKUP_V1: consult only; never create or retry a sale. */
    [HttpGet("status/{key:guid}")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Status(Guid key, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Inicia sesiÃ³n" });
        if (key == Guid.Empty) return BadRequest(new { message = "Clave invÃ¡lida" });
        var valid = await (from business in db.Businesses.AsNoTracking()
                           join branch in db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
                           join device in db.Devices.AsNoTracking() on branch.Id equals device.BranchId
                           join user in db.Users.AsNoTracking() on business.Id equals user.BusinessId
                           where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active
                              && branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active
                              && device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active
                              && device.Mode == "PointOfSale" && tenant.DeviceMode == "PointOfSale"
                              && user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active
                              && user.Role == tenant.Role
                           select user.Id).AnyAsync(ct);
        if (!valid || tenant.Role is not ("Administrator" or "Manager" or "Supervisor" or "Seller"))
            return StatusCode(403, new { message = "Identidad no autorizada" });
        var sale = await db.Sales.AsNoTracking()
            .Where(s => s.BusinessId == tenant.BusinessId && s.BranchId == tenant.BranchId
                     && s.DeviceId == tenant.DeviceId && s.UserId == tenant.UserId
                     && s.IdempotencyKey == key)
            .Select(s => new { s.GlobalId, s.Folio, s.TotalCents, s.SaleDateTime, s.Status })
            .SingleOrDefaultAsync(ct);
        if (sale is null) return NotFound(new { state = "not_found", message = "Sin confirmaciÃ³n. No se autoriza un nuevo cobro." });
        if (sale.Status != "Confirmed") return Conflict(new { state = "unresolved", message = "RevisiÃ³n administrativa requerida." });
        return Ok(new { state = "confirmed", saleGlobalId = sale.GlobalId, sale.Folio,
            sale.TotalCents, sale.SaleDateTime });
    }
}
