using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using PosFlutter.Web.Models;
using PosFlutter.Web.Services;
namespace PosFlutter.Web.Controllers;
public sealed class HomeController(WebTenantSession tenants):Controller {
 private bool LoggedIn => WebTenantSession.Read(HttpContext.Session) is not null;
 [HttpGet] public IActionResult Index() => LoggedIn?View():RedirectToAction(nameof(Login));
 [HttpGet] public IActionResult Login() => LoggedIn?RedirectToAction(nameof(Index)):View(new LoginForm());
 [HttpPost,ValidateAntiForgeryToken,EnableRateLimiting("web-login")] public async Task<IActionResult> Login(LoginForm form,CancellationToken ct) {
  if(!ModelState.IsValid || form.BusinessGlobalId==Guid.Empty || form.DeviceGlobalId==Guid.Empty) {ModelState.AddModelError("","Datos de acceso incompletos");return View(form);}
  try {
   var tenant=await tenants.LoginAsync(form.BusinessGlobalId,form.DeviceGlobalId,form.Username,form.Password,ct);
   if(tenant is null) {ModelState.AddModelError("","Acceso rechazado");return View(form);}
   HttpContext.Session.Clear(); WebTenantSession.Store(HttpContext.Session,tenant);
   return RedirectToAction(nameof(Index));
  } catch(Exception ex) when(ex is InvalidOperationException or TaskCanceledException) {ModelState.AddModelError("","Servidor de datos no disponible");return View(form);}
 }
 [HttpPost,ValidateAntiForgeryToken] public IActionResult Logout() {HttpContext.Session.Clear();return RedirectToAction(nameof(Login));}
 [HttpGet] public IActionResult Error() => View();
}
