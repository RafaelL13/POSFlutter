using System.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Configuration;
using Pos.Domain;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

public sealed record AdminInventoryAdjustmentCommitRequest(
    Guid ProductGlobalId, int QuantityDelta, string? Reason,
    Guid IdempotencyKey, long? UnitCostCents);

public sealed partial class AdminInventoryAdjustmentsController
{
    // Explicitly pinned to an isolated, disposable MVC LAB database and loopback host.
    private bool CanCommitLab(IConfiguration config)
    {
        var expected = config["AdminCatalog:LabDatabaseName"];
        var actual = db.Database.GetDbConnection().Database;
        var port = config.GetValue<int>("AdminCatalog:LabPort");
        return config.GetValue<bool>("AdminCatalog:AllowLabWrites") &&
            !string.IsNullOrWhiteSpace(expected) &&
            expected.StartsWith("POSFlutter_MvcLab_", StringComparison.OrdinalIgnoreCase) &&
            string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase) &&
            port is > 1024 and <= 65535 &&
            string.Equals(Request.Host.Host, "localhost", StringComparison.OrdinalIgnoreCase) &&
            Request.Host.Port == port;
    }

    [HttpPost("commit")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Commit(
        [FromBody] AdminInventoryAdjustmentCommitRequest? request,
        [FromServices] IConfiguration config, CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null) return Unauthorized();
        if (tenant.Role != "Administrator") return StatusCode(403);
        if (!CanCommitLab(config)) return StatusCode(423, new { code = "LAB_WRITES_DISABLED" });
        if (request is null || request.ProductGlobalId == Guid.Empty ||
            request.IdempotencyKey == Guid.Empty || request.QuantityDelta == 0 ||
            request.QuantityDelta == int.MinValue ||
            Math.Abs((long)request.QuantityDelta) > 1000000 ||
            string.IsNullOrWhiteSpace(request.Reason) ||
            request.Reason.Trim().Length is < 5 or > 240 ||
            (request.QuantityDelta > 0 && (request.UnitCostCents is null or < 0)) ||
            (request.QuantityDelta < 0 && request.UnitCostCents is not null))
            return BadRequest(new { code = "INVALID_ADJUSTMENT_REQUEST" });

        var valid = await db.Businesses.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId && x.Active, ct)
            && await db.Branches.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.BranchId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.BranchGlobalId && x.Active, ct)
            && await db.Users.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.UserId && x.BusinessId == tenant.BusinessId &&
                x.GlobalId == tenant.UserGlobalId && x.Active && x.Role == "Administrator", ct)
            && await db.Devices.AsNoTracking().AnyAsync(x =>
                x.Id == tenant.DeviceId && x.BranchId == tenant.BranchId &&
                x.GlobalId == tenant.DeviceGlobalId && x.Active, ct);
        if (!valid) return StatusCode(403);

        // SQL Server serializable transaction plus an application lock per tenant/branch.
        // All adjustment requests for this branch are serialized, including replays.
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var connection = db.Database.GetDbConnection();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = tx.GetDbTransaction();
            command.CommandText = "DECLARE @r int; EXEC @r = sys.sp_getapplock @Resource=@resource, @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=10000; SELECT @r;";
            var p = command.CreateParameter();
            p.ParameterName = "@resource";
            p.Value = $"posweb:adjust:{tenant.BusinessId}:{tenant.BranchId}";
            command.Parameters.Add(p);
            var lockResult = Convert.ToInt32(await command.ExecuteScalarAsync(ct));
            if (lockResult < 0) return StatusCode(409, new { code = "ADJUSTMENT_BUSY" });
        }

        // Reject cross-product or changed-payload reuse of an idempotency key.
        var auditNote = request.Reason!.Trim() + (request.QuantityDelta > 0 ? $" | unitCostCents={request.UnitCostCents!.Value}" : "");
        var prior = await db.InventoryMovements.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
                        x.ReferenceGlobalId == request.IdempotencyKey &&
                        (x.Type == "AdjustmentIn" || x.Type == "AdjustmentOut"))
            .OrderBy(x => x.Id).ToListAsync(ct);
        if (prior.Count > 0)
        {
            if (prior.Any(x => x.ProductGlobalId != request.ProductGlobalId ||
                    x.Notes != auditNote || x.UserId != tenant.UserId || x.DeviceId != tenant.DeviceId) ||
                prior.Sum(x => (long)x.QuantityDelta) != request.QuantityDelta ||
                prior.Any(x => x.Type != (request.QuantityDelta > 0 ? "AdjustmentIn" : "AdjustmentOut")))
                return Conflict(new { code = "IDEMPOTENCY_KEY_CONFLICT" });
            return Ok(new { replay = true, referenceGlobalId = request.IdempotencyKey });
        }

        var productExists = await db.Products.AsNoTracking().AnyAsync(x =>
            x.BusinessId == tenant.BusinessId && x.GlobalId == request.ProductGlobalId && x.Active, ct);
        if (!productExists) return NotFound(new { code = "PRODUCT_NOT_FOUND" });

        var lots = await db.InventoryLots.Where(x =>
            x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId &&
            x.ProductGlobalId == request.ProductGlobalId && x.Active)
            .OrderBy(x => x.EntryDate).ThenBy(x => x.Id).ToListAsync(ct);
        var current = lots.Sum(x => (long)x.AvailableQuantity);
        var next = current + request.QuantityDelta;
        if (next < 0) return Conflict(new { code = "INSUFFICIENT_STOCK" });
        if (next > int.MaxValue) return Conflict(new { code = "STOCK_OVERFLOW" });
        var now = DateTimeOffset.UtcNow;
        if (request.QuantityDelta > 0)
        {
            db.InventoryLots.Add(new InventoryLot {
                GlobalId = Guid.NewGuid(), BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId, ProductGlobalId = request.ProductGlobalId,
                EntryDate = now, CreatedAt = now, InitialQuantity = request.QuantityDelta,
                AvailableQuantity = request.QuantityDelta,
                UnitCostCents = request.UnitCostCents!.Value, Active = true
            });
        }
        else
        {
            var remaining = -(long)request.QuantityDelta;
            foreach (var lot in lots)
            {
                if (remaining == 0) break;
                var taken = (int)Math.Min(remaining, lot.AvailableQuantity);
                lot.AvailableQuantity -= taken;
                remaining -= taken;
            }
            if (remaining != 0) return Conflict(new { code = "INSUFFICIENT_STOCK" });
        }
        db.InventoryMovements.Add(new InventoryMovement {
            GlobalId = Guid.NewGuid(), BusinessId = tenant.BusinessId,
            BranchId = tenant.BranchId, ProductGlobalId = request.ProductGlobalId,
            MovementDate = now, Type = request.QuantityDelta > 0 ? "AdjustmentIn" : "AdjustmentOut",
            QuantityDelta = request.QuantityDelta,
            PreviousStock = checked((int)current), NewStock = checked((int)next),
            ReferenceGlobalId = request.IdempotencyKey,
            UserId = tenant.UserId, DeviceId = tenant.DeviceId, Notes = auditNote
        });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return Ok(new { replay = false, referenceGlobalId = request.IdempotencyKey,
            previousStock = current, newStock = next });
    }
}
