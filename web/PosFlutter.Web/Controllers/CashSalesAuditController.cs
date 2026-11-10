using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

/// <summary>
/// Strictly read-only sales/payment-to-cash-session attribution preview.
/// Time/device/user matching is provisional: it does not authorize closing cash.
/// </summary>
[Route("cash-operations")]
public sealed class CashSalesAuditController(PosDbContext db) : Controller
{
    [HttpGet("sales-audit")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> SalesAudit(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized(new { message = "Sesion requerida" });
        if (!string.Equals(tenant.Role, "Administrator", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(tenant.DeviceMode, "PointOfSale", StringComparison.OrdinalIgnoreCase))
            return StatusCode(403, new { message = "Operador no autorizado" });

        var valid = await (from business in db.Businesses.AsNoTracking()
                           join branch in db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
                           join device in db.Devices.AsNoTracking() on branch.Id equals device.BranchId
                           join user in db.Users.AsNoTracking() on business.Id equals user.BusinessId
                           where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active &&
                               branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active &&
                               device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active &&
                               device.Mode == tenant.DeviceMode && user.Id == tenant.UserId &&
                               user.GlobalId == tenant.UserGlobalId && user.Active && user.Role == tenant.Role
                           select business.Id).AnyAsync(ct);
        if (!valid) { HttpContext.Session.Clear(); return StatusCode(403, new { message = "Identidad inactiva" }); }

        var open = await db.CashSessions.AsNoTracking()
            .Where(c => c.BusinessId == tenant.BusinessId && c.BranchId == tenant.BranchId &&
                c.DeviceId == tenant.DeviceId && c.UserId == tenant.UserId && c.Status == "Open")
            .Select(c => new { c.Id, c.GlobalId, c.OpenedAt, c.OpeningBalanceCents })
            .Take(2).ToListAsync(ct);
        if (open.Count != 1) return Conflict(new { message = "Se requiere exactamente una caja abierta", openCount = open.Count });
        var session = open[0];
        var now = DateTimeOffset.UtcNow;
        // Limit to this tenant/branch and open session time; Never expose other tenants.
        var sales = await db.Sales.AsNoTracking()
            .Where(s => s.BusinessId == tenant.BusinessId && s.BranchId == tenant.BranchId &&
                s.SaleDateTime >= session.OpenedAt && s.SaleDateTime <= now && s.Status == "Confirmed")
            .Select(s => new { s.Id, s.GlobalId, s.DeviceId, s.UserId, s.SaleDateTime,
                s.TotalCents, s.PaymentMethod }).ToListAsync(ct);
        var ids = sales.Select(s => s.Id).ToArray();
        var payments = await db.SalePayments.AsNoTracking()
            .Where(p => ids.Contains(p.SaleId) && p.Method == "Cash")
            .Select(p => new { p.SaleId, p.AmountCents }).ToListAsync(ct);
        var paymentBySale = payments.GroupBy(p => p.SaleId)
            .ToDictionary(g => g.Key, g => g.Sum(p => p.AmountCents));
        var matched = sales.Where(s => s.DeviceId == tenant.DeviceId && s.UserId == tenant.UserId).ToList();
        var other = sales.Where(s => s.DeviceId != tenant.DeviceId || s.UserId != tenant.UserId).ToList();
        var cashCents = matched.Sum(s => paymentBySale.GetValueOrDefault(s.Id));
        var unmatchedCash = other.Sum(s => paymentBySale.GetValueOrDefault(s.Id));
        var legacyNoCashRecord = matched.Count(s => s.PaymentMethod == "Cash" && !paymentBySale.ContainsKey(s.Id));
        var movements = await db.CashMovements.AsNoTracking()
            .Where(m => m.BusinessId == tenant.BusinessId && m.CashSessionId == session.Id)
            .Select(m => new { m.Type, m.AmountCents }).ToListAsync(ct);
        var movementDelta = movements.Sum(m => m.AmountCents);
        var expenses = await db.Expenses.AsNoTracking()
            .Where(e => e.BusinessId == tenant.BusinessId && e.BranchId == tenant.BranchId &&
                e.DeviceId == tenant.DeviceId && e.UserId == tenant.UserId &&
                e.ExpenseDate >= session.OpenedAt && e.ExpenseDate <= now && e.PaymentMethod == "Cash")
            .Select(e => e.AmountCents).ToListAsync(ct);
        var expenseCents = expenses.Sum();
        var warnings = new List<string>();
        if (unmatchedCash != 0) warnings.Add("Existen cobros en efectivo de otros dispositivos o usuarios en la sucursal.");
        if (legacyNoCashRecord > 0) warnings.Add("Hay ventas Cash sin SalePayment Cash documentado.");
        if (expenseCents > 0) warnings.Add("Los gastos en efectivo pueden duplicarse con movimientos ManualOut: asociacion no confirmada.");
        warnings.Add("Ventas y pagos carecen de CashSessionId: atribucion provisional por usuario, dispositivo y tiempo.");
        var provisional = checked(session.OpeningBalanceCents + movementDelta + cashCents - expenseCents);
        return Ok(new {
            cashSessionGlobalId = session.GlobalId, session.OpenedAt,
            openingBalanceCents = session.OpeningBalanceCents,
            matchedSaleCount = matched.Count, matchedCashPaymentsCents = cashCents,
            otherDeviceCashPaymentsCents = unmatchedCash,
            salesMissingCashPaymentCount = legacyNoCashRecord,
            movementCount = movements.Count, manualDeltaCents = movementDelta,
            cashExpenseCount = expenses.Count, cashExpenseCents = expenseCents,
            provisionalExpectedCents = provisional,
            warnings, requiresReview = true, closeAuthorized = false,
            attribution = "PROVISIONAL_TIME_DEVICE_USER", generatedAt = now
        });
    }
}