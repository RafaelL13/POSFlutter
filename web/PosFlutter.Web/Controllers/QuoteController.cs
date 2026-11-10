using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc;
using PosFlutter.Web.Models;
using PosFlutter.Web.Services;
using Pos.Infrastructure;

namespace PosFlutter.Web.Controllers;

// Preview only. No sales, payment, inventory writes or reliance on browser-supplied prices.
[Route("quote")]
public sealed class QuoteController(PosDbContext db) : Controller {
 [HttpPost("calculate"), ValidateAntiForgeryToken, RequestSizeLimit(32768)]
 public async Task<IActionResult> Calculate([FromBody] QuoteRequest request, CancellationToken ct) {
  if (!ModelState.IsValid || request.Lines.Count is < 1 or > 100 ||
      request.Lines.Any(x=>x.ProductGlobalId==Guid.Empty || x.Quantity is < 1 or > 100000) ||
      request.Lines.GroupBy(x=>x.ProductGlobalId).Any(x=>x.Count()!=1))
   return BadRequest(new {message="Artículos inválidos o repetidos"});
  var tenant=WebTenantSession.Read(HttpContext.Session);
  if (tenant is null) return Unauthorized(new {message="Sesión requerida"});
  try {
   var products=new Dictionary<Guid,(string Name,long Price)>();
   var ids=request.Lines.Select(x=>x.ProductGlobalId).ToArray();
   var rows=await db.Products.AsNoTracking().Where(x=>x.BusinessId==tenant.BusinessId && x.Active && ids.Contains(x.GlobalId)).Select(x=>new{x.GlobalId,x.Name,x.SalePriceCents}).ToListAsync(ct);
   foreach(var row in rows) products[row.GlobalId]=(row.Name,row.SalePriceCents);
   long total=0;
   var result=new List<object>();
   foreach(var line in request.Lines) {
    if(!products.TryGetValue(line.ProductGlobalId,out var product))
     return Conflict(new {message="Producto ya no disponible. Actualiza el catálogo."});
    var subtotal=checked(product.Price*line.Quantity);
    total=checked(total+subtotal);
    result.Add(new {productGlobalId=line.ProductGlobalId,name=product.Name,quantity=line.Quantity,unitPriceCents=product.Price,subtotalCents=subtotal});
   }
   return Ok(new {lines=result,totalCents=total,quotedAt=DateTimeOffset.UtcNow,confirmed=false,
      message="Cotización recalculada con precios centrales; no reserva inventario ni registra venta."});
  } catch(OverflowException) {return BadRequest(new {message="Importe fuera de rango"});}
    catch(Exception ex) when(ex is TaskCanceledException or InvalidOperationException) {
     return StatusCode(502,new {message="No fue posible validar precios centrales"});
    }
 }
}
