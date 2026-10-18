using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

[Route("purchases")]
public sealed class PurchasesController(PosDbContext db, PurchaseReceivingService receiving) : Controller
{
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create([FromBody] PurchaseSyncPayload request, CancellationToken ct)
    {
        var tenant=WebTenantSession.Read(HttpContext.Session);
        if(tenant is null) return Unauthorized();
        if(!string.Equals(tenant.Role,"Administrator",StringComparison.OrdinalIgnoreCase)) return Forbid();
        if(request.BusinessGlobalId!=tenant.BusinessGlobalId || request.BranchGlobalId!=tenant.BranchGlobalId || request.DeviceGlobalId!=tenant.DeviceGlobalId || request.UserGlobalId!=tenant.UserGlobalId) return BadRequest(new {message="Contexto de compra inválido"});
        await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        try {
            var prior=await db.Purchases.SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == request.GlobalId, ct);
            if(prior is not null) { await tx.CommitAsync(ct); return Ok(new {globalId=prior.GlobalId,replay=true}); }
            var purchase=await receiving.ReceiveAsync(request,tenant,ct);
            db.SyncChanges.Add(new Pos.Domain.SyncChange { BusinessId=tenant.BusinessId,EntityType="Purchase",EntityGlobalId=purchase.GlobalId,Operation="Create",Version=1,PayloadJson=JsonSerializer.Serialize(request),CreatedAt=DateTimeOffset.UtcNow });
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            return Ok(new {globalId=purchase.GlobalId,totalCents=purchase.TotalCents,replay=false});
        } catch(ArgumentException ex){return BadRequest(new {message=ex.Message});} catch(InvalidOperationException ex){return Conflict(new {message=ex.Message});}
    }
}
