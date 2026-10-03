using Microsoft.EntityFrameworkCore;
using Pos.Application;

namespace Pos.Infrastructure;

public sealed class InternalPosAdminTenantResolver(PosDbContext db)
{
    private readonly PosDbContext _db = db;

    public async Task<SyncTenantContext?> ResolveAsync(
        Guid businessGlobalId,
        CancellationToken cancellationToken)
    {
        if (businessGlobalId == Guid.Empty)
        {
            return null;
        }

        var business = await _db.Businesses.AsNoTracking()
            .SingleOrDefaultAsync(
                x => x.GlobalId == businessGlobalId && x.Active,
                cancellationToken);

        if (business is null)
        {
            return null;
        }

        var user = await _db.Users.AsNoTracking()
            .Where(
                x =>
                    x.BusinessId == business.Id &&
                    x.Active &&
                    x.Role == "Administrator")
            .OrderBy(x => x.Id)
            .FirstOrDefaultAsync(cancellationToken);

        if (user is null)
        {
            return null;
        }

        var deviceContext = await (
            from device in _db.Devices.AsNoTracking()
            join branch in _db.Branches.AsNoTracking()
                on device.BranchId equals branch.Id
            where
                branch.BusinessId == business.Id &&
                branch.Active &&
                device.Active &&
                (device.Mode == "AdminReadOnly" ||
                 device.Mode == "PointOfSale")
            orderby
                device.Mode == "AdminReadOnly" ? 0 : 1,
                branch.Id,
                device.Id
            select new
            {
                BranchId = branch.Id,
                BranchGlobalId = branch.GlobalId,
                DeviceId = device.Id,
                DeviceGlobalId = device.GlobalId,
                device.Mode
            })
            .FirstOrDefaultAsync(cancellationToken);

        if (deviceContext is null)
        {
            return null;
        }

        return new SyncTenantContext(
            business.Id,
            business.GlobalId,
            deviceContext.BranchId,
            deviceContext.BranchGlobalId,
            deviceContext.DeviceId,
            deviceContext.DeviceGlobalId,
            user.Id,
            user.GlobalId,
            user.Role,
            deviceContext.Mode);
    }
}
