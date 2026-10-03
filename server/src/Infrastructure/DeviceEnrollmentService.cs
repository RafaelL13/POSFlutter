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
    private const string PointOfSaleMode = "PointOfSale";
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
        var requestedMode = NormalizeMode(request.Mode);
        var now = DateTimeOffset.UtcNow;
        var rawToken = GenerateEnrollmentCode();
        _db.DeviceEnrollmentTokens.Add(new DeviceEnrollmentToken
        {
            TokenHash = HashToken(rawToken),
            BusinessId = tenant.BusinessId,
            BranchId = branch.Id,
            CreatedByUserId = tenant.UserId,
            RequestedMode = requestedMode,
            CreatedAt = now,
            ExpiresAt = now.AddMinutes(minutes)
        });
        await _db.SaveChangesAsync(cancellationToken);

        return new DeviceEnrollmentInvitation(
            rawToken,
            tenant.BusinessGlobalId,
            branch.GlobalId,
            now.AddMinutes(minutes),
            requestedMode);
    }

    public async Task<DeviceEnrollmentInvitation> CreateRecoveryInvitationAsync(
        SyncTenantContext tenant,
        CreateDeviceRecoveryInvitationRequest request,
        CancellationToken cancellationToken)
    {
        if (tenant.Role != AdministratorRole)
            throw new UnauthorizedAccessException("Only administrators can recover devices.");

        if (request.DeviceGlobalId == Guid.Empty)
            throw new ArgumentException("DeviceGlobalId is required.", nameof(request));

        var branch = await _db.Branches.AsNoTracking().SingleOrDefaultAsync(
            x => x.Id == tenant.BranchId &&
                 x.GlobalId == tenant.BranchGlobalId &&
                 x.BusinessId == tenant.BusinessId &&
                 x.Active,
            cancellationToken)
            ?? throw new UnauthorizedAccessException(
                "The authenticated branch is not active.");

        var device = await _db.Devices.AsNoTracking().SingleOrDefaultAsync(
            x => x.GlobalId == request.DeviceGlobalId &&
                 x.BranchId == branch.Id &&
                 x.Active,
            cancellationToken)
            ?? throw new InvalidOperationException(
                "The device is not active in the authenticated branch.");

        var minutes = Math.Clamp(
            request.ExpiresInMinutes ?? 15,
            5,
            30);

        var now = DateTimeOffset.UtcNow;
        var rawToken = GenerateEnrollmentCode();

        _db.DeviceEnrollmentTokens.Add(
            new DeviceEnrollmentToken
            {
                TokenHash = HashToken(rawToken),
                BusinessId = tenant.BusinessId,
                BranchId = branch.Id,
                CreatedByUserId = tenant.UserId,
                RequestedMode = device.Mode,
                CreatedAt = now,
                ExpiresAt = now.AddMinutes(minutes),

                // A recovery invitation represents an enrollment
                // that already completed on the server.
                UsedAt = now,
                DeviceId = device.Id
            });

        await _db.SaveChangesAsync(cancellationToken);

        return new DeviceEnrollmentInvitation(
            rawToken,
            tenant.BusinessGlobalId,
            branch.GlobalId,
            now.AddMinutes(minutes),
            device.Mode);
    }
    public async Task<EnrolledAdministrativeDevice?> RedeemAsync(
        RedeemDeviceEnrollmentRequest request,
        CancellationToken cancellationToken)
    {
        var token = NormalizeEnrollmentToken(request.Token);
        var username = request.Username.Trim();
        var deviceName = request.DeviceName.Trim();
        if (!IsValidEnrollmentToken(token) || request.DeviceGlobalId == Guid.Empty || deviceName.Length is < 2 or > 120 ||
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
                Mode = invitation.RequestedMode,
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
                 x.Mode == invitation.RequestedMode,
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

    private static string NormalizeMode(string? mode)
    {
        var normalized = mode?.Trim();

        return normalized switch
        {
            PointOfSaleMode => PointOfSaleMode,
            AdminReadOnlyMode => AdminReadOnlyMode,
            _ => throw new ArgumentOutOfRangeException(
                nameof(mode),
                "Device mode must be PointOfSale or AdminReadOnly.")
        };
    }
    private static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    private const string EnrollmentCodeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
    private const int EnrollmentCodeLength = 8;

    private static string GenerateEnrollmentCode()
    {
        Span<char> chars = stackalloc char[EnrollmentCodeLength];

        for (var i = 0; i < chars.Length; i++)
        {
            chars[i] = EnrollmentCodeAlphabet[
                RandomNumberGenerator.GetInt32(EnrollmentCodeAlphabet.Length)];
        }

        return new string(chars);
    }

    private static string NormalizeEnrollmentToken(string token)
    {
        if (string.IsNullOrWhiteSpace(token))
            return string.Empty;

        return token
            .Trim()
            .Replace("-", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .ToUpperInvariant();
    }

    private static bool IsValidEnrollmentToken(string token)
    {
        if (token.Length == EnrollmentCodeLength)
            return token.All(EnrollmentCodeAlphabet.Contains);

        // Backward compatibility for invitations generated before
        // the short-code enrollment contract.
        return token.Length >= 20;
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
