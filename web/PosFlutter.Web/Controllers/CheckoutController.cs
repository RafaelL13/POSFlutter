using Microsoft.AspNetCore.Mvc;
using Pos.Application;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("checkout")]
public sealed class CheckoutController(WebCheckoutService checkout) : Controller
{
    [HttpPost]
    [RequestSizeLimit(32768)]
    public async Task<IActionResult> Create([FromBody] WebCheckoutRequest request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Inicia sesión" });
        try { return Ok(await checkout.CheckoutAsync(request, tenant, ct)); }
        catch (UnauthorizedAccessException) { HttpContext.Session.Clear(); return StatusCode(403, new { message = "Acceso denegado" }); }
        catch (ArgumentException) { return BadRequest(new { message = "Checkout inválido" }); }
        catch (InvalidOperationException) { return Conflict(new { message = "Stock insuficiente o conflicto" }); }
    }
}
