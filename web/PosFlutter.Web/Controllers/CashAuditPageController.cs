using Microsoft.AspNetCore.Mvc;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("cash-audit")]
public sealed class CashAuditPageController : Controller
{
    [HttpGet("")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public IActionResult Index()
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return RedirectToAction("Login", "Home");
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(tenant.DeviceMode, "PointOfSale", StringComparison.OrdinalIgnoreCase))
            return StatusCode(403);
        return View();
    }
}