using System.ComponentModel.DataAnnotations;
using System.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Domain;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

public sealed class ExpensePost
{
    [Required] public Guid OperationGlobalId { get; set; }
    public Guid? CashSessionGlobalId { get; set; }
    [Required, StringLength(160)] public string Concept { get; set; } = "";
    [StringLength(80)] public string? Category { get; set; }
    [Range(1, 100000000)] public long AmountCents { get; set; }
    [Required, RegularExpression("^(Cash|Card|Transfer|Other)$")] public string PaymentMethod { get; set; } = "";
    [StringLength(240)] public string? Notes { get; set; }
}

[Route("expenses")]
public sealed class ExpensesController(PosDbContext db) : Controller
{
    [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(8192)]
    public async Task<IActionResult> Create([FromBody] ExpensePost request, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(tenant.DeviceMode, "PointOfSale", StringComparison.OrdinalIgnoreCase)) return Forbid();
        if (request is null || !ModelState.IsValid || request.OperationGlobalId == Guid.Empty ||
            string.IsNullOrWhiteSpace(request.Concept) || (request.PaymentMethod == "Cash") != request.CashSessionGlobalId.HasValue)
            return BadRequest(new { message = "Gasto invalido o sesión de caja incongruente" });
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var existing = await db.Expenses.SingleOrDefaultAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == request.OperationGlobalId, ct);
        if (existing is not null)
        {
            if (existing.AmountCents != request.AmountCents || existing.PaymentMethod != request.PaymentMethod || existing.Concept != request.Concept.Trim())
                return Conflict(new { message = "Identificador ya utilizado" });
            await tx.CommitAsync(ct); return Ok(new { globalId = existing.GlobalId, replay = true });
        }
        CashSession? session = null;
        if (request.PaymentMethod == "Cash")
        {
            session = await db.CashSessions.SingleOrDefaultAsync(x => x.GlobalId == request.CashSessionGlobalId &&
                x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId && x.DeviceId == tenant.DeviceId &&
                x.UserId == tenant.UserId && x.Status == "Open", ct);
            if (session is null) return Conflict(new { message = "Caja abierta no encontrada" });
        }
        var now = DateTimeOffset.UtcNow;
        var expense = new Expense { GlobalId = request.OperationGlobalId, BusinessId = tenant.BusinessId, BranchId = tenant.BranchId,
            DeviceId = tenant.DeviceId, UserId = tenant.UserId, CashSessionId = session?.Id, ExpenseDate = now,
            Concept = request.Concept.Trim(), Category = request.Category?.Trim(), AmountCents = request.AmountCents,
            PaymentMethod = request.PaymentMethod, Notes = request.Notes?.Trim(), CreatedAt = now };
        db.Expenses.Add(expense);
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
        return Ok(new { globalId = expense.GlobalId, cashSessionGlobalId = session?.GlobalId, replay = false });
    }
}
