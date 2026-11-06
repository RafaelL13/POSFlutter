using Microsoft.AspNetCore.Mvc;
using PosFlutter.Web.Services;
namespace PosFlutter.Web.Controllers;
[Route("supervision")]
public sealed class SupervisionController : Controller
{
    [HttpGet] public IActionResult Index() => WebTenantSession.Read(HttpContext.Session) is null ? Unauthorized() : View();
}
