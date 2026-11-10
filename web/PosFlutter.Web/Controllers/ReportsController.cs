using Microsoft.AspNetCore.Mvc;
using Pos.Infrastructure;
using PosFlutter.Web.Services;
using Pos.Application;

namespace PosFlutter.Web.Controllers;

/// <summary>Read-only reports using existing scoped backend authorization.</summary>
[Route("reports")]
public sealed class ReportsController(TenantReadService reads, RemoteReportService reports) : Controller
{
    private static ReportPeriod Period(DateTimeOffset? from, DateTimeOffset? to)
    {
        var end=(to ?? DateTimeOffset.UtcNow).ToUniversalTime(); var start=(from ?? end.AddDays(-30)).ToUniversalTime();
        if(start>=end || end-start>TimeSpan.FromDays(366)) throw new ArgumentException("Invalid report period.");
        return new(start,end);
    }

    [HttpGet("")]
    public IActionResult Index() => WebTenantSession.Read(HttpContext.Session) is null ? Unauthorized() : View("Admin");

    private static SalesReportFilter Filter(Guid? branch,Guid? user,Guid? product,string? payment,string? status,string? sort,bool? descending) =>
        new(branch,user,product,payment,status,sort ?? "date",descending ?? true);

    [HttpGet("admin")]
    [ResponseCache(NoStore=true,Location=ResponseCacheLocation.None)]
    public async Task<IActionResult> Admin(DateTimeOffset? from, DateTimeOffset? to, int? page, Guid? branch, Guid? user, Guid? product, string? payment, string? status, string? sort, bool? descending, CancellationToken cancellationToken)
    {
        var tenant=WebTenantSession.Read(HttpContext.Session); if(tenant is null)return Unauthorized(new{message="Sesion requerida"});
        try { var period=Period(from,to); var p=Math.Clamp(page??1,1,100000);
            return Ok(new { period, summary=await reports.SummaryAsync(tenant,period,cancellationToken),
                sales=await reports.SaleDetailsAsync(tenant,period,p,50,Filter(branch,user,product,payment,status,sort,descending),cancellationToken),
                products=await reports.ProductsAsync(tenant,period,"profit",true,50,cancellationToken),
                inventory=await reports.InventoryAsync(tenant,cancellationToken),
                payments=await reports.PaymentMethodsAsync(tenant,period,cancellationToken),
                cancellations=await reports.CancellationsAsync(tenant,period,p,50,cancellationToken) }); }
        catch(UnauthorizedAccessException){HttpContext.Session.Clear();return StatusCode(403,new{message="Acceso denegado"});}
        catch(ArgumentException){return BadRequest(new{message="Periodo inválido"});}
    }

    [HttpGet("export/sales/{format}")]
    [ResponseCache(NoStore=true,Location=ResponseCacheLocation.None)]
    public async Task<IActionResult> Export(string format,DateTimeOffset? from,DateTimeOffset? to,Guid? branch,Guid? user,Guid? product,string? payment,string? status,string? sort,bool? descending,CancellationToken cancellationToken)
    {
        var tenant=WebTenantSession.Read(HttpContext.Session); if(tenant is null)return Unauthorized();
        try {
            var period=Period(from,to); var rows=(await reports.SaleDetailsAsync(tenant,period,1,200,Filter(branch,user,product,payment,status,sort,descending),cancellationToken)).Items;
            var bytes=ReportExportWriter.Write(format,rows,period); var extension=format.ToLowerInvariant();
            var content=extension switch { "csv"=>"text/csv; charset=utf-8", "xlsx"=>"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "pdf"=>"application/pdf", _=>throw new ArgumentException("Unsupported export format.") };
            return File(bytes,content,$"reporte-ventas-{period.From:yyyyMMdd}.{extension}");
        } catch(UnauthorizedAccessException){HttpContext.Session.Clear();return StatusCode(403);} catch(ArgumentException ex){return BadRequest(new {message=ex.Message});}
    }
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
