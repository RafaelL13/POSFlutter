using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Api;

/// <summary>Opt-in pull for upgraded clients only. The legacy sync route remains supported.</summary>
public static class WebSalePullEndpoint
{
    public static void Map(WebApplication app)
    {
        app.MapGet("/api/sync/pull-v2", async (
            long? cursor, int? limit, HttpContext http, PosDbContext db, CancellationToken ct) =>
        {
            if (!WebSaleSyncCapability.IsSupported(http.Request.Headers[WebSaleSyncCapability.Header].ToString()))
                return Results.BadRequest(new { message = "WebSaleInventoryV1 capability is required." });

            var tenant = TenantClaims.Require(http.User);
            if (tenant.DeviceId <= 0 || tenant.BusinessId <= 0 || tenant.BranchId <= 0 ||
                tenant.DeviceMode != "PointOfSale")
                return Results.Forbid();

            // Claims alone do not prove the enrolled device is still active.
            var active = await (
                from device in db.Devices.AsNoTracking()
                join branch in db.Branches.AsNoTracking() on device.BranchId equals branch.Id
                join business in db.Businesses.AsNoTracking() on branch.BusinessId equals business.Id
                where device.Id == tenant.DeviceId &&
                      device.GlobalId == tenant.DeviceGlobalId &&
                      device.BranchId == tenant.BranchId &&
                      device.Active && device.Mode == "PointOfSale" &&
                      branch.Id == tenant.BranchId &&
                      branch.GlobalId == tenant.BranchGlobalId && branch.Active &&
                      business.Id == tenant.BusinessId &&
                      business.GlobalId == tenant.BusinessGlobalId && business.Active
                select device.Id
            ).AnyAsync(ct);
            if (!active) return Results.Forbid();

            if (cursor.GetValueOrDefault() < 0) return Results.BadRequest(new { message = "Invalid cursor." });
            var after = cursor.GetValueOrDefault();
            var take = Math.Clamp(limit.GetValueOrDefault(100), 1, 200);

            var rows = await db.SyncChanges.AsNoTracking()
                .Where(x => x.BusinessId == tenant.BusinessId && x.Id > after)
                .OrderBy(x => x.Id)
                .Take(take + 1)
                .ToListAsync(ct);
            var hasMore = rows.Count > take;
            if (hasMore) rows.RemoveAt(rows.Count - 1);

            var changes = new List<SyncPullChange>(rows.Count);
            foreach (var row in rows)
            {
                using var document = JsonDocument.Parse(row.PayloadJson);
                changes.Add(new SyncPullChange(row.Id, row.EntityType,
                    row.EntityGlobalId, row.Operation, row.Version,
                    row.CreatedAt, document.RootElement.Clone()));
            }
            return Results.Ok(new SyncPullResponse(
                changes.Count == 0 ? after : changes[^1].Cursor,
                hasMore, changes, DateTimeOffset.UtcNow));
        }).RequireAuthorization();
    }
}
