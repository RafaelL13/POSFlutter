using Microsoft.AspNetCore.Mvc;
using PosFlutter.Web.Services;
namespace PosFlutter.Web.Controllers;
[Route("device-monitor")]
public sealed class DeviceMonitorController : Controller
{
    [HttpGet] public IActionResult Index() => WebTenantSession.Read(HttpContext.Session) is null ? Unauthorized() : View();
}
