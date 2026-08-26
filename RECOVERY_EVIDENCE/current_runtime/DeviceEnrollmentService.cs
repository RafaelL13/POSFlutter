using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class DeviceEnrollmentService(PosDbContext db, ITokenService tokens)
{
    private const string AdministratorRole = "Administrator";
    private const string AdminReadOnlyMode = "AdminReadOnly";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly PosDbContext _db = db;
    private readonly ITokenService _tokens = tokens;

    public async Task<DeviceEnrollmentInvitation> CreateInvitationAsync(
        SyncTenantContext tenant,
        CreateDeviceEnrollmentRequest request,
        CancellationToken cancellationToken)
    {
        if (tenant.Role != AdministratorRole)
            throw new UnauthorizedAccessException("Only administrators can enroll devices.");

        var branch = await _db.Branches.AsNoTracking().SingleOrDefaultAsync(
            x => x.Id == tenant.BranchId && x.GlobalId == tenant.BranchGlobalId &&
                 x.BusinessId == tenant.BusinessId && x.Active,
            cancellationToken)
            ?? throw new UnauthorizedAccessException("The authenticated branch is not active.");

        var minutes = Math.Clamp(request.ExpiresInMinutes ?? 15, 5, 30);
        var now = DateTimeOffset.UtcNow;
        var rawToken = Base64Url(RandomNumberGenerator.GetBytes(32));
        _db.DeviceEnrollmentTokens.Add(new DeviceEnrollmentToken
        {
            TokenHash = HashToken(rawToken),
            BusinessId = tenant.BusinessId,
            BranchId = branch.Id,
            CreatedByUserId = tenant.UserId,
            CreatedAt = now,
            ExpiresAt = now.AddMinutes(minutes)
        });
        await _db.SaveChangesAsync(cancellationToken);

        return new DeviceEnrollmentInvitation(
            rawToken,
            tenant.BusinessGlobalId,
            branch.GlobalId,
            now.AddMinutes(minutes));
    }

    public async Task<EnrolledAdministrativeDevice?> RedeemAsync(
        RedeemDeviceEnrollmentRequest request,
        CancellationToken cancellationToken)
    {
        var token = request.Token.Trim();
        var username = request.Username.Trim();
        var deviceName = request.DeviceName.Trim();
        if (token.Length < 20 || request.DeviceGlobalId == Guid.Empty || deviceName.Length is < 2 or > 120 ||
            username.Length < 3 || request.Password.Length < 8)
            return null;

        var now = DateTimeOffset.UtcNow;
        await using var transaction = await _db.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        try
        {
            var invitation = await _db.DeviceEnrollmentTokens.SingleOrDefaultAsync(
                x => x.TokenHash == HashToken(token),
                cancellationToken);
            if (invitation is null || invitation.ExpiresAt <= now || invitation.RevokedAt is not null)
            {
                await transaction.RollbackAsync(cancellationToken);
                return null;
            }

            var business = await _db.Businesses.SingleOrDefaultAsync(
                x => x.Id == invitation.BusinessId && x.Active,
                cancellationToken);
            var branch = await _db.Branches.SingleOrDefaultAsync(
                x => x.Id == invitation.BranchId && x.BusinessId == invitation.BusinessId && x.Active,
                cancellationToken);
            var user = await _db.Users.SingleOrDefaultAsync(
                x => x.BusinessId == invitation.BusinessId && x.Username == username && x.Active,
                cancellationToken);
            if (business is null || branch is null || user is null || user.Role != AdministratorRole ||
                !PasswordHashing.Verify(request.Password, user.PasswordHash, user.PasswordSalt))
            {
                await transaction.RollbackAsync(cancellationToken);
                return null;
            }

            if (invitation.UsedAt is not null)
            {
                var recovered = await RecoverCompletedEnrollmentAsync(
                    invitation,
                    business,
                    branch,
                    user,
                    request,
                    username,
                    cancellationToken);
                if (recovered is null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    _db.ChangeTracker.Clear();
                    return null;
                }

                await transaction.CommitAsync(cancellationToken);
                return recovered;
            }

            if (await _db.Devices.AnyAsync(x => x.GlobalId == request.DeviceGlobalId, cancellationToken))
            {
                await transaction.RollbackAsync(cancellationToken);
                return null;
            }

            var device = new Device
            {
                GlobalId = request.DeviceGlobalId,
                BranchId = branch.Id,
                Name = deviceName,
                Mode = AdminReadOnlyMode,
                Active = true,
                CreatedAt = now,
                LastSyncAt = now,
                ServerVersion = 1
            };
            _db.Devices.Add(device);
            await _db.SaveChangesAsync(cancellationToken);

            invitation.UsedAt = now;
            invitation.DeviceId = device.Id;
            var devicePayload = new DevicePullPayload(
                device.GlobalId,
                business.GlobalId,
                branch.GlobalId,
                device.Name,
                device.Mode,
                device.Active,
                device.LastSyncAt,
                device.ServerVersion);
            _db.SyncChanges.Add(new SyncChange
            {
                BusinessId = business.Id,
                EntityType = "Device",
                EntityGlobalId = device.GlobalId,
                Operation = "Create",
                Version = device.ServerVersion,
                PayloadJson = JsonSerializer.Serialize(devicePayload, JsonOptions),
                CreatedAt = now
            });
            await _db.SaveChangesAsync(cancellationToken);

            var auth = await _tokens.LoginAsync(
                new LoginRequest(business.GlobalId, device.GlobalId, username, request.Password),
                cancellationToken);
            if (auth is null)
            {
                await transaction.RollbackAsync(cancellationToken);
                _db.ChangeTracker.Clear();
                return null;
            }

            await transaction.CommitAsync(cancellationToken);
            return new EnrolledAdministrativeDevice(
                business.GlobalId,
                business.Name,
                business.ServerVersion,
                branch.GlobalId,
                branch.Name,
                branch.ServerVersion,
                device.GlobalId,
                device.Name,
                device.Mode,
                device.ServerVersion,
                user.GlobalId,
                user.Name,
                user.Username,
                user.Role,
                user.ServerVersion,
                auth);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            _db.ChangeTracker.Clear();
            throw;
        }
    }

    private async Task<EnrolledAdministrativeDevice?> RecoverCompletedEnrollmentAsync(
        DeviceEnrollmentToken invitation,
        Business business,
        Branch branch,
        UserAccount user,
        RedeemDeviceEnrollmentRequest request,
        string username,
        CancellationToken cancellationToken)
    {
        if (invitation.DeviceId is null) return null;

        var device = await _db.Devices.AsNoTracking().SingleOrDefaultAsync(
            x => x.Id == invitation.DeviceId.Value &&
                 x.GlobalId == request.DeviceGlobalId &&
                 x.BranchId == branch.Id &&
                 x.Active &&
                 x.Mode == AdminReadOnlyMode,
            cancellationToken);
        if (device is null) return null;

        var auth = await _tokens.LoginAsync(
            new LoginRequest(business.GlobalId, device.GlobalId, username, request.Password),
            cancellationToken);
        if (auth is null) return null;

        return new EnrolledAdministrativeDevice(
            business.GlobalId,
            business.Name,
            business.ServerVersion,
            branch.GlobalId,
            branch.Name,
            branch.ServerVersion,
            device.GlobalId,
            device.Name,
            device.Mode,
            device.ServerVersion,
            user.GlobalId,
            user.Name,
            user.Username,
            user.Role,
            user.ServerVersion,
            auth);
    }

    private static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
