using Microsoft.AspNetCore.Mvc;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// Each backend read method validates active tenant, device, user and capability.
// Never bypass TenantReadService with unrestricted MVC database queries.
[Route("data")]
public sealed class DataController(TenantReadService reads) : Controller
{
    private async Task<IActionResult> Read(Func<Pos.Application.SyncTenantContext, CancellationToken, Task<object>> operation, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Inicia sesiÃ³n" });
        try { return Json(new { items = await operation(tenant, ct) }); }
        catch (UnauthorizedAccessException)
        {
            HttpContext.Session.Clear();
            return StatusCode(403, new { message = "Acceso denegado" });
        }
    }

    [HttpGet("dashboard")]
    public Task<IActionResult> Dashboard(CancellationToken ct) => Read(async (t,c) => await reads.DashboardAsync(t,c), ct);
    [HttpGet("products")]
    public Task<IActionResult> Products(CancellationToken ct) => Read(async (t,c) => await reads.ProductsAsync(t,c), ct);
    [HttpGet("inventory")]
    public Task<IActionResult> Inventory(CancellationToken ct) => Read(async (t,c) => await reads.InventoryAsync(t,c), ct);
    [HttpGet("lots")]
    public Task<IActionResult> Lots(CancellationToken ct) => Read(async (t,c) => await reads.LotsAsync(t,c), ct);
    [HttpGet("sales")]
    public Task<IActionResult> Sales(CancellationToken ct) => Read(async (t,c) => await reads.SalesAsync(t,c), ct);
    [HttpGet("purchases")]
    public Task<IActionResult> Purchases(CancellationToken ct) => Read(async (t,c) => await reads.PurchasesAsync(t,c), ct);
    [HttpGet("cash")]
    public Task<IActionResult> Cash(CancellationToken ct) => Read(async (t,c) => await reads.CashAsync(t,c), ct);
    [HttpGet("expenses")]
    public Task<IActionResult> Expenses(CancellationToken ct) => Read(async (t,c) => await reads.ExpensesAsync(t,c), ct);
    [HttpGet("devices")]
    public Task<IActionResult> Devices(CancellationToken ct) => Read(async (t,c) => await reads.DevicesAsync(t,c), ct);
    [HttpGet("branches")]
    public Task<IActionResult> Branches(CancellationToken ct) => Read(async (t,c) => await reads.BranchesAsync(t,c), ct);
    [HttpGet("users")]
    public Task<IActionResult> Users(CancellationToken ct) => Read(async (t,c) => await reads.UsersAsync(t,c), ct);
    [HttpGet("categories")]
    public Task<IActionResult> Categories(CancellationToken ct) => Read(async (t,c) => await reads.CategoriesAsync(t,c), ct);
    [HttpGet("suppliers")]
    public Task<IActionResult> Suppliers(CancellationToken ct) => Read(async (t,c) => await reads.SuppliersAsync(t,c), ct);
}