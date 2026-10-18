using System.ComponentModel.DataAnnotations;
using System.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Domain;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

public sealed class CashMovementPost
{
    [Required]
    public Guid CashSessionGlobalId { get; set; }
    [Required]
    public Guid OperationGlobalId { get; set; }
    [Required, RegularExpression("^(In|Out)$")]
    public string Type { get; set; } = "";
    [Range(1, 100000000)]
    public long AmountCents { get; set; }
    [MaxLength(240)]
    public string? Notes { get; set; }
}

[Route("cash-operations")]
public sealed class CashMovementsController(PosDbContext db) : Controller
{
    [HttpPost("movement"), ValidateAntiForgeryToken, RequestSizeLimit(8192)]
    public async Task<IActionResult> Record([FromBody] CashMovementPost request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (tenant.Role != "Administrator" || tenant.DeviceMode != "PointOfSale")
            return StatusCode(403, new { message = "Acceso restringido" });
        if (request is null || !ModelState.IsValid || request.CashSessionGlobalId == Guid.Empty ||
            request.OperationGlobalId == Guid.Empty ||
            (request.Type != "In" && request.Type != "Out") ||
            request.AmountCents < 1 || request.AmountCents > 100000000)
            return BadRequest(new { message = "Movimiento invalido" });

        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            var authorized = await (
                from b in db.Businesses.AsNoTracking()
                join br in db.Branches.AsNoTracking() on b.Id equals br.BusinessId
                join d in db.Devices.AsNoTracking() on br.Id equals d.BranchId
                join u in db.Users.AsNoTracking() on b.Id equals u.BusinessId
                where b.Id == tenant.BusinessId && b.GlobalId == tenant.BusinessGlobalId && b.Active &&
                      br.Id == tenant.BranchId && br.GlobalId == tenant.BranchGlobalId && br.Active &&
                      d.Id == tenant.DeviceId && d.GlobalId == tenant.DeviceGlobalId && d.Active &&
                      d.Mode == "PointOfSale" && u.Id == tenant.UserId &&
                      u.GlobalId == tenant.UserGlobalId && u.Active && u.Role == "Administrator"
                select b.Id).AnyAsync(ct);
            if (!authorized) return StatusCode(403, new { message = "Identidad no autorizada" });

            var session = await db.CashSessions
                .SingleOrDefaultAsync(x => x.GlobalId == request.CashSessionGlobalId &&
                    x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
                    x.DeviceId == tenant.DeviceId && x.UserId == tenant.UserId, ct);
            if (session is null) return NotFound(new { message = "Caja no encontrada" });
            if (session.Status != "Open" || session.ClosedAt != null)
                return Conflict(new { message = "Caja cerrada" });

            // API accepts In/Out with a positive magnitude. SQL schema requires
            // ManualIn/positive and ManualOut/negative (CK_CashMovement_*).
            var dbType = request.Type == "In" ? "ManualIn" : "ManualOut";
            var signedAmount = request.Type == "In" ? request.AmountCents : -request.AmountCents;
            var existing = await db.CashMovements.AsNoTracking()
                .SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId &&
                    x.GlobalId == request.OperationGlobalId, ct);
            if (existing is not null)
            {
                if (existing.CashSessionId != session.Id || existing.UserId != tenant.UserId ||
                    existing.Type != dbType || existing.AmountCents != signedAmount ||
                    existing.Notes != request.Notes)
                    return Conflict(new { message = "Identificador ya utilizado" });
                await tx.CommitAsync(ct);
                return Ok(new { globalId = existing.GlobalId, replay = true });
            }

            var movement = new CashMovement
            {
                GlobalId = request.OperationGlobalId,
                BusinessId = tenant.BusinessId,
                CashSessionId = session.Id,
                UserId = tenant.UserId,
                MovementDate = DateTimeOffset.UtcNow,
                Type = dbType,
                AmountCents = signedAmount,
                Notes = request.Notes
            };
            db.CashMovements.Add(movement);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return Ok(new { globalId = movement.GlobalId, replay = false });
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "Movimiento en conflicto" });
        }
    }
}