using Microsoft.AspNetCore.Mvc;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("sales/cancel")]
public sealed class SaleCancellationsController(WebSaleCancellationService cancellations) : Controller
{
    [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(8192)]
    public async Task<IActionResult> Cancel([FromBody] WebSaleCancellationRequest request, CancellationToken ct)
    {
        var tenant=WebTenantSession.Read(HttpContext.Session); if(tenant is null)return Unauthorized(new{message="Inicia sesión"});
        try{return Ok(await cancellations.CancelAsync(request,tenant,ct));}
        catch(UnauthorizedAccessException){return StatusCode(403,new{message="No autorizado"});}
        catch(KeyNotFoundException){return NotFound(new{message="Venta no encontrada"});}
        catch(ArgumentException){return BadRequest(new{message="Cancelación inválida"});}
        catch(InvalidOperationException){return Conflict(new{message="La devolución o la venta no permite cancelación"});}
    }
}
