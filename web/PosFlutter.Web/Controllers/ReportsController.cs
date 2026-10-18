using Microsoft.AspNetCore.Mvc;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

/// <summary>Read-only reports using existing scoped backend authorization.</summary>
[Route("reports")]
public sealed class ReportsController(TenantReadService reads) : Controller
{
    [HttpGet("summary")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Summary(CancellationToken cancellationToken)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        try
        {
            // Both operations enforce current user/device/business authorization in SQL.
            var dashboard = await reads.DashboardAsync(tenant, cancellationToken);
            var sales = await reads.SalesAsync(tenant, cancellationToken);
            return Ok(new { dashboard, sales, generatedAt = DateTimeOffset.UtcNow,
                scope = "authorized", maxSales = 500 });
        }
        catch (UnauthorizedAccessException)
        {
            HttpContext.Session.Clear();
            return StatusCode(403, new { message = "Acceso denegado" });
        }
    }

    // Export mirrors the pre-authorized SalesAsync projection. Sensitive cost fields
    // are absent for users without permission and are never retrieved separately.
    [HttpGet("export-sales.csv")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> ExportSales(CancellationToken cancellationToken)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        try
        {
            var rows = await reads.SalesAsync(tenant, cancellationToken);
            var csv = new System.Text.StringBuilder();
            csv.AppendLine("Folio,Fecha,ImporteMXN,Estado,CostoFifoMXN,UtilidadBrutaMXN");
            foreach (var row in rows)
            {
                var j = System.Text.Json.JsonSerializer.SerializeToElement(row);
                string Field(string key)
                {
                    if (!j.TryGetProperty(key, out var v) || v.ValueKind == System.Text.Json.JsonValueKind.Null)
                        return "";
                    return v.ValueKind == System.Text.Json.JsonValueKind.String ? v.GetString() ?? "" : v.ToString();
                }
                string Money(string key)
                {
                    if (!j.TryGetProperty(key, out var v) || v.ValueKind != System.Text.Json.JsonValueKind.Number)
                        return "";
                    return (v.GetDecimal() / 100m).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);
                }
                static string EscapeCell(string? raw)
                {
                    var value = (raw ?? "").Replace("\r", " ").Replace("\n", " ").Trim();
                    // Excel formula injection can occur even with quoted CSV cells.
                    if (value.Length > 0 && "=+-@".Contains(value[0])) value = "'" + value;
                    return "\"" + value.Replace("\"", "\"\"") + "\"";
                }
                csv.AppendLine(string.Join(",", new[] {
                    EscapeCell(Field("Folio")), EscapeCell(Field("SaleDateTime")),
                    EscapeCell(Money("TotalCents")), EscapeCell(Field("Status")),
                    EscapeCell(Money("FifoCostCents")), EscapeCell(Money("GrossProfitCents"))
                }));
            }
            var utf8 = new System.Text.UTF8Encoding(true);
            var bytes = utf8.GetPreamble().Concat(utf8.GetBytes(csv.ToString())).ToArray();
            return File(bytes, "text/csv; charset=utf-8", "ventas-autorizadas.csv");
        }
        catch (UnauthorizedAccessException)
        {
            HttpContext.Session.Clear();
            return StatusCode(403);
        }
    }
}