using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;

namespace PosFlutter.Web.Services;

public sealed class WebTenantSession(PosDbContext db)
{
    public async Task<SyncTenantContext?> LoginAsync(Guid businessGlobalId, Guid deviceGlobalId, string username, string password, CancellationToken ct)
    {
        var row = await (from business in db.Businesses.AsNoTracking()
                         join branch in db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
                         join device in db.Devices.AsNoTracking() on branch.Id equals device.BranchId
                         join user in db.Users.AsNoTracking() on business.Id equals user.BusinessId
                         where business.GlobalId == businessGlobalId && business.Active &&
                               device.GlobalId == deviceGlobalId && device.Active && branch.Active &&
                               user.Username == username && user.Active
                         select new { business, branch, device, user }).SingleOrDefaultAsync(ct);
        if (row is null || !PasswordHashing.Verify(password, row.user.PasswordHash, row.user.PasswordSalt)) return null;
        return new SyncTenantContext(row.business.Id, row.business.GlobalId, row.branch.Id, row.branch.GlobalId,
            row.device.Id, row.device.GlobalId, row.user.Id, row.user.GlobalId, row.user.Role, row.device.Mode);
    }

    public static void Store(ISession session, SyncTenantContext tenant)
    {
        session.SetString("tenant", string.Join('|', tenant.BusinessId, tenant.BusinessGlobalId, tenant.BranchId,
            tenant.BranchGlobalId, tenant.DeviceId, tenant.DeviceGlobalId, tenant.UserId, tenant.UserGlobalId, tenant.Role, tenant.DeviceMode));
    }

    public static SyncTenantContext? Read(ISession session)
    {
        var values = session.GetString("tenant")?.Split('|');
        if (values is not { Length: 10 } || !long.TryParse(values[0], out var businessId) || !Guid.TryParse(values[1], out var businessGid) ||
            !long.TryParse(values[2], out var branchId) || !Guid.TryParse(values[3], out var branchGid) || !long.TryParse(values[4], out var deviceId) ||
            !Guid.TryParse(values[5], out var deviceGid) || !long.TryParse(values[6], out var userId) || !Guid.TryParse(values[7], out var userGid)) return null;
        return new SyncTenantContext(businessId, businessGid, branchId, branchGid, deviceId, deviceGid, userId, userGid, values[8], values[9]);
    }
}
