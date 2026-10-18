using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

public sealed class CashOpenInput
{
    public long OpeningBalanceCents { get; set; }
}

// Stateful endpoint: transaction and authorization are checked inside the operation.
[Route("cash-operations")]
public sealed class CashOperationsController(PosDbContext db, TenantReadService reads) : Controller
{
    [HttpPost("open")]
    [ValidateAntiForgeryToken]
    [RequestSizeLimit(8192)]
    public async Task<IActionResult> Open([FromBody] CashOpenInput? input, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (input is null || input.OpeningBalanceCents < 0 || input.OpeningBalanceCents > 100000000L)
            return BadRequest(new { message = "Saldo inicial invalido" });
        // Fail closed until cashier write roles are formalized in the backend.
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(tenant.DeviceMode, "PointOfSale", StringComparison.OrdinalIgnoreCase))
            return StatusCode(403, new { message = "No autorizado para abrir caja" });
        try
        {
            // This also checks active tenant/user/device and the existing CashRead capability.
            await reads.CashAsync(tenant, ct);
            await using var transaction = await db.Database.BeginTransactionAsync(
                System.Data.IsolationLevel.Serializable, ct);
            // Revalidate active tenant membership within the writing transaction.
            var allowed = await (from business in db.Businesses
                                 join branch in db.Branches on business.Id equals branch.BusinessId
                                 join device in db.Devices on branch.Id equals device.BranchId
                                 join user in db.Users on business.Id equals user.BusinessId
                                 where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active &&
                                       branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active &&
                                       device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active &&
                                       device.Mode == tenant.DeviceMode &&
                                       user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active && user.Role == tenant.Role
                                 select user.Id).AnyAsync(ct);
            if (!allowed) return StatusCode(403, new { message = "Sesion revocada" });
            var alreadyOpen = await db.CashSessions.AnyAsync(x =>
                x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
                x.DeviceId == tenant.DeviceId && x.Status == "Open", ct);
            if (alreadyOpen) return Conflict(new { message = "La caja ya esta abierta en este dispositivo" });
            var now = DateTimeOffset.UtcNow;
            var session = new Pos.Domain.CashSession
            {
                GlobalId = Guid.NewGuid(), BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId, DeviceId = tenant.DeviceId, UserId = tenant.UserId,
                OpenedAt = now, OpeningBalanceCents = input.OpeningBalanceCents,
                Status = "Open", UpdatedAt = now
            };
            db.CashSessions.Add(session);
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Ok(new { session.GlobalId, session.OpenedAt, session.OpeningBalanceCents, session.Status });
        }
        catch (UnauthorizedAccessException)
        {
            HttpContext.Session.Clear();
            return StatusCode(403, new { message = "Acceso revocado" });
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "Conflicto al abrir caja" });
        }
    }

    public sealed class CashCloseInput
    {
        public Guid SessionGlobalId { get; set; }
        public long CountedCashCents { get; set; }
    }

    // Closure derives the balance from immutable links to this exact session.
    [HttpPost("close")]
    [ValidateAntiForgeryToken]
    [RequestSizeLimit(8192)]
    public async Task<IActionResult> Close([FromBody] CashCloseInput? input, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (input is null || input.SessionGlobalId == Guid.Empty ||
            input.CountedCashCents < 0 || input.CountedCashCents > 100000000L)
            return BadRequest(new { message = "Datos de cierre invalidos" });
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(tenant.DeviceMode, "PointOfSale", StringComparison.OrdinalIgnoreCase))
            return StatusCode(403, new { message = "No autorizado para cerrar caja" });
        try
        {
            await reads.CashAsync(tenant, ct);
            await using var tx = await db.Database.BeginTransactionAsync(
                System.Data.IsolationLevel.Serializable, ct);
            var valid = await (from b in db.Businesses
                               join br in db.Branches on b.Id equals br.BusinessId
                               join d in db.Devices on br.Id equals d.BranchId
                               join u in db.Users on b.Id equals u.BusinessId
                               where b.Id == tenant.BusinessId && b.GlobalId == tenant.BusinessGlobalId && b.Active &&
                                     br.Id == tenant.BranchId && br.GlobalId == tenant.BranchGlobalId && br.Active &&
                                     d.Id == tenant.DeviceId && d.GlobalId == tenant.DeviceGlobalId && d.Active && d.Mode == tenant.DeviceMode &&
                                     u.Id == tenant.UserId && u.GlobalId == tenant.UserGlobalId && u.Active && u.Role == tenant.Role
                               select u.Id).AnyAsync(ct);
            if (!valid) return StatusCode(403, new { message = "Sesion revocada" });
            var session = await db.CashSessions.SingleOrDefaultAsync(x =>
                x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
                x.DeviceId == tenant.DeviceId && x.GlobalId == input.SessionGlobalId, ct);
            if (session is null) return NotFound(new { message = "Caja no encontrada" });
            if (session.Status != "Open") return Conflict(new { message = "La caja ya esta cerrada" });
            var manualDelta = await db.CashMovements
                .Where(x => x.BusinessId == tenant.BusinessId && x.CashSessionId == session.Id)
                .Select(x => (long?)x.AmountCents).SumAsync(ct) ?? 0;
            var linkedCashSales = await (from payment in db.SalePayments
                                         join sale in db.Sales on payment.SaleId equals sale.Id
                                         where payment.CashSessionId == session.Id && payment.Method == "Cash"
                                             && sale.BusinessId == tenant.BusinessId && sale.Status == "Confirmed"
                                         select (long?)payment.AmountCents).SumAsync(ct) ?? 0;
            var unlinkedCashPayments = await (from payment in db.SalePayments
                                              join sale in db.Sales on payment.SaleId equals sale.Id
                                              where payment.CashSessionId == null && payment.Method == "Cash"
                                                  && sale.BusinessId == tenant.BusinessId && sale.BranchId == tenant.BranchId
                                                  && sale.DeviceId == tenant.DeviceId && sale.UserId == tenant.UserId
                                                  && sale.SaleDateTime >= session.OpenedAt && sale.Status == "Confirmed"
                                              select payment.Id).AnyAsync(ct);
            var unlinkedCashExpenses = await db.Expenses.AnyAsync(x =>
                x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
                x.DeviceId == tenant.DeviceId && x.UserId == tenant.UserId &&
                x.ExpenseDate >= session.OpenedAt && x.PaymentMethod == "Cash", ct);
            if (unlinkedCashPayments || unlinkedCashExpenses)
                return Conflict(new { message = "Hay actividad Cash heredada sin vínculo persistente a la sesión" });
            long expected;
            try { expected = checked(checked(session.OpeningBalanceCents + manualDelta) + linkedCashSales); }
            catch (OverflowException) { return Conflict(new { message = "Desbordamiento en la conciliación de caja" }); }
            var now = DateTimeOffset.UtcNow;
            session.ExpectedCashCents = expected;
            session.CountedCashCents = input.CountedCashCents;
            session.DifferenceCents = checked(input.CountedCashCents - expected);
            session.Status = "Closed";
            session.ClosedAt = now;
            session.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return Ok(new { session.GlobalId, session.Status, session.ClosedAt,
                session.ExpectedCashCents, session.CountedCashCents, session.DifferenceCents,
                scope = "cash-session-persistent-links" });
        }
        catch (UnauthorizedAccessException)
        {
            HttpContext.Session.Clear();
            return StatusCode(403, new { message = "Acceso revocado" });
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "Conflicto al cerrar caja" });
        }
    }
}
