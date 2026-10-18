using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

/// <summary>
/// Read-only cash preview. Only rows persistently linked to the cash session affect totals.
/// </summary>
[Route("cash-operations")]
public sealed class CashReconciliationController(PosDbContext db) : Controller
{
    [HttpGet("reconciliation-preview")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Preview(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (tenant.Role != "Administrator" || tenant.DeviceMode != "PointOfSale")
            return Forbid();

        var identityIsActive = await (
            from business in db.Businesses.AsNoTracking()
            join branch in db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
            join device in db.Devices.AsNoTracking() on branch.Id equals device.BranchId
            join user in db.Users.AsNoTracking() on business.Id equals user.BusinessId
            where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active
                && branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active
                && device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active
                && device.Mode == tenant.DeviceMode
                && user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active
                && user.Role == tenant.Role
            select user.Id).AnyAsync(ct);
        if (!identityIsActive) { HttpContext.Session.Clear(); return StatusCode(403, new { message = "Tenant inactivo" }); }

        var sessions = await db.CashSessions.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId
                && x.DeviceId == tenant.DeviceId && x.UserId == tenant.UserId && x.Status == "Open")
            .OrderByDescending(x => x.OpenedAt).Take(2).ToListAsync(ct);
        if (sessions.Count != 1)
            return Conflict(new { message = "Se requiere exactamente una caja abierta", openCount = sessions.Count });

        var cash = sessions[0];
        var movements = await db.CashMovements.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.CashSessionId == cash.Id)
            .Select(x => new { x.Type, x.AmountCents, x.MovementDate }).ToListAsync(ct);
        var linkedPayments = await (from payment in db.SalePayments.AsNoTracking()
                                    join sale in db.Sales.AsNoTracking() on payment.SaleId equals sale.Id
                                    where payment.CashSessionId == cash.Id && payment.Method == "Cash"
                                        && sale.BusinessId == tenant.BusinessId && sale.Status == "Confirmed"
                                    select payment.AmountCents).ToListAsync(ct);
        // Older rows cannot safely be assigned retroactively. They deliberately keep
        // closure blocked instead of being guessed from a timestamp or user identity.
        var unlinkedCashPayments = await (from payment in db.SalePayments.AsNoTracking()
                                          join sale in db.Sales.AsNoTracking() on payment.SaleId equals sale.Id
                                          where payment.CashSessionId == null && payment.Method == "Cash"
                                              && sale.BusinessId == tenant.BusinessId && sale.BranchId == tenant.BranchId
                                              && sale.DeviceId == tenant.DeviceId && sale.UserId == tenant.UserId
                                              && sale.SaleDateTime >= cash.OpenedAt && sale.Status == "Confirmed"
                                          select payment.Id).CountAsync(ct);
        var unlinkedCashExpenses = await db.Expenses.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId
                && x.DeviceId == tenant.DeviceId && x.UserId == tenant.UserId
                && x.ExpenseDate >= cash.OpenedAt && x.PaymentMethod == "Cash")
            .CountAsync(ct);

        var warnings = new List<string>();
        if (movements.Any(x => x.Type != "ManualIn" && x.Type != "ManualOut"))
            warnings.Add("Movimiento de caja desconocido");
        if (movements.Any(x => (x.Type == "ManualIn" && x.AmountCents <= 0)
            || (x.Type == "ManualOut" && x.AmountCents >= 0)))
            warnings.Add("Movimiento de caja con signo incorrecto");
        if (unlinkedCashPayments > 0) warnings.Add("Hay cobros Cash heredados sin CashSessionId; el cierre queda bloqueado.");
        if (unlinkedCashExpenses > 0) warnings.Add("Hay gastos Cash sin vínculo de sesión; el cierre queda bloqueado.");

        long manualDelta, cashSales, provisionalExpected;
        try
        {
            manualDelta = movements.Aggregate(0L, (sum, x) => checked(sum + x.AmountCents));
            cashSales = linkedPayments.Aggregate(0L, (sum, amount) => checked(sum + amount));
            provisionalExpected = checked(checked(cash.OpeningBalanceCents + manualDelta) + cashSales);
        }
        catch (OverflowException)
        {
            return Conflict(new { message = "Desbordamiento de importes; conciliacion detenida" });
        }
        return Ok(new {
            cashSessionGlobalId = cash.GlobalId, cash.OpenedAt,
            cash.OpeningBalanceCents,
            manualMovementCount = movements.Count, manualDeltaCents = manualDelta,
            linkedCashPaymentsCount = linkedPayments.Count, linkedCashSalesCents = cashSales,
            expectedCashCents = provisionalExpected,
            unlinkedCashPayments, unlinkedCashExpenses,
            warnings, requiresReview = warnings.Count > 0, closeAuthorized = warnings.Count == 0,
            scope = "cash-session-persistent-links",
            generatedAt = DateTimeOffset.UtcNow,
            explanation = "El saldo usa exclusivamente pagos Cash vinculados a esta sesión y movimientos de caja."
        });
    }
}
