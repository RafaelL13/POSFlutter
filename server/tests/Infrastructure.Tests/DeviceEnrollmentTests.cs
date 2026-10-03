using System.Text.Json;
using Pos.Application;

namespace Pos.Infrastructure.Tests;

public sealed class DeviceEnrollmentTests
{
    [Theory]
    [InlineData("PointOfSale")]
    [InlineData("AdminReadOnly")]
    public async Task Invitation_preserves_authorized_device_mode(string mode)
    {
        await using var t = await TestDatabase.CreateAsync();
        var a = await t.SeedTenantAsync($"MODE-{mode}");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        var invitation =
            await service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(15, mode),
                CancellationToken.None);

        Assert.Equal(mode, invitation.Mode);

        var stored =
            t.Db.DeviceEnrollmentTokens.Single();

        Assert.Equal(mode, stored.RequestedMode);

        Assert.DoesNotContain(
            invitation.Code,
            stored.TokenHash,
            StringComparison.Ordinal);

        var deviceGlobalId =
            Guid.NewGuid();

        var request =
            new RedeemDeviceEnrollmentRequest(
                invitation.Code,
                a.User.Username,
                "StrongPass123!",
                $"{mode} tablet",
                deviceGlobalId);

        var first =
            await service.RedeemAsync(
                request,
                CancellationToken.None);

        var retry =
            await service.RedeemAsync(
                request,
                CancellationToken.None);

        Assert.NotNull(first);
        Assert.NotNull(retry);

        Assert.Equal(mode, first!.DeviceMode);
        Assert.Equal(mode, retry!.DeviceMode);

        Assert.Single(
            t.Db.Devices.Where(
                x =>
                    x.GlobalId == deviceGlobalId &&
                    x.Mode == mode));
    }

    [Fact]
    public async Task Legacy_invitation_request_defaults_to_admin_read_only()
    {
        await using var t = await TestDatabase.CreateAsync();
        var a = await t.SeedTenantAsync("LEGACY");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        var invitation =
            await service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(15),
                CancellationToken.None);

        Assert.Equal("AdminReadOnly", invitation.Mode);

        Assert.Equal(
            "AdminReadOnly",
            t.Db.DeviceEnrollmentTokens.Single().RequestedMode);
    }

    [Fact]
    public async Task Invalid_invitation_mode_is_rejected()
    {
        await using var t = await TestDatabase.CreateAsync();
        var a = await t.SeedTenantAsync("INVALID");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(
                    15,
                    "Owner"),
                CancellationToken.None));

        Assert.Empty(t.Db.DeviceEnrollmentTokens);
    }

    [Fact]
    public async Task Revoked_invitation_is_rejected()
    {
        await using var t = await TestDatabase.CreateAsync();
        var a = await t.SeedTenantAsync("REVOKED");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        var invitation =
            await service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(
                    15,
                    "PointOfSale"),
                CancellationToken.None);

        var token =
            t.Db.DeviceEnrollmentTokens.Single();

        token.RevokedAt =
            DateTimeOffset.UtcNow;

        await t.Db.SaveChangesAsync(TestContext.Current.CancellationToken);

        var result =
            await service.RedeemAsync(
                new RedeemDeviceEnrollmentRequest(
                    invitation.Code,
                    a.User.Username,
                    "StrongPass123!",
                    "Tablet",
                    Guid.NewGuid()),
                CancellationToken.None);

        Assert.Null(result);
    }

    [Fact]
    public async Task Seller_cannot_create_invitation()
    {
        await using var t = await TestDatabase.CreateAsync();
        var a =
            await t.SeedTenantAsync(
                "SELLER",
                role: "Seller");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(
                    15,
                    "PointOfSale"),
                CancellationToken.None));
    }

    [Fact]
    public async Task Other_business_admin_cannot_redeem_invitation()
    {
        await using var t = await TestDatabase.CreateAsync();

        var a =
            await t.SeedTenantAsync("TENANT-A");

        var b =
            await t.SeedTenantAsync("TENANT-B");

        var service =
            new DeviceEnrollmentService(
                t.Db,
                new FakeTokenService());

        var context =
            new SyncTenantContext(
                a.Business.Id,
                a.Business.GlobalId,
                a.Branch.Id,
                a.Branch.GlobalId,
                a.Device.Id,
                a.Device.GlobalId,
                a.User.Id,
                a.User.GlobalId,
                a.User.Role,
                a.Device.Mode);

        var invitation =
            await service.CreateInvitationAsync(
                context,
                new CreateDeviceEnrollmentRequest(
                    15,
                    "PointOfSale"),
                CancellationToken.None);

        var result =
            await service.RedeemAsync(
                new RedeemDeviceEnrollmentRequest(
                    invitation.Code,
                    b.User.Username,
                    "StrongPass123!",
                    "Foreign tablet",
                    Guid.NewGuid()),
                CancellationToken.None);

        Assert.Null(result);

        Assert.Null(
            t.Db.DeviceEnrollmentTokens
                .Single()
                .UsedAt);
    }


    [Fact]
    public async Task Recovery_invitation_reuses_existing_device_without_creating_duplicate()
    {
        await using var t = await TestDatabase.CreateAsync();
        var a = await t.SeedTenantAsync("RECOVERY");

        var service = new DeviceEnrollmentService(
            t.Db,
            new FakeTokenService());

        var context = new SyncTenantContext(
            a.Business.Id,
            a.Business.GlobalId,
            a.Branch.Id,
            a.Branch.GlobalId,
            a.Device.Id,
            a.Device.GlobalId,
            a.User.Id,
            a.User.GlobalId,
            a.User.Role,
            a.Device.Mode);

        var deviceGlobalId = Guid.NewGuid();

        var invitation = await service.CreateInvitationAsync(
            context,
            new CreateDeviceEnrollmentRequest(
                15,
                "PointOfSale"),
            CancellationToken.None);

        var first = await service.RedeemAsync(
            new RedeemDeviceEnrollmentRequest(
                invitation.Code,
                a.User.Username,
                "StrongPass123!",
                "Recovery tablet",
                deviceGlobalId),
            CancellationToken.None);

        Assert.NotNull(first);

        var existingDevice = t.Db.Devices.Single(
            x => x.GlobalId == deviceGlobalId);

        var deviceCountBefore =
            t.Db.Devices.Count(
                x => x.GlobalId == deviceGlobalId);

        var recovery =
            await service.CreateRecoveryInvitationAsync(
                context,
                new CreateDeviceRecoveryInvitationRequest(
                    deviceGlobalId,
                    15),
                CancellationToken.None);

        Assert.Equal("PointOfSale", recovery.Mode);

        var storedRecovery =
            t.Db.DeviceEnrollmentTokens
                .OrderByDescending(x => x.Id)
                .First();

        Assert.Equal(
            existingDevice.Id,
            storedRecovery.DeviceId);

        Assert.NotNull(storedRecovery.UsedAt);

        var recovered = await service.RedeemAsync(
            new RedeemDeviceEnrollmentRequest(
                recovery.Code,
                a.User.Username,
                "StrongPass123!",
                "Recovery tablet",
                deviceGlobalId),
            CancellationToken.None);

        Assert.NotNull(recovered);

        Assert.Equal(
            deviceGlobalId,
            recovered!.DeviceGlobalId);

        Assert.Equal(
            deviceCountBefore,
            t.Db.Devices.Count(
                x => x.GlobalId == deviceGlobalId));
    }

    [Fact]
    public async Task Recovery_invitation_rejects_device_outside_authenticated_branch()
    {
        await using var t = await TestDatabase.CreateAsync();

        var a = await t.SeedTenantAsync("RECOVERY-A");
        var b = await t.SeedTenantAsync("RECOVERY-B");

        var service = new DeviceEnrollmentService(
            t.Db,
            new FakeTokenService());

        var context = new SyncTenantContext(
            a.Business.Id,
            a.Business.GlobalId,
            a.Branch.Id,
            a.Branch.GlobalId,
            a.Device.Id,
            a.Device.GlobalId,
            a.User.Id,
            a.User.GlobalId,
            a.User.Role,
            a.Device.Mode);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.CreateRecoveryInvitationAsync(
                context,
                new CreateDeviceRecoveryInvitationRequest(
                    b.Device.GlobalId,
                    15),
                CancellationToken.None));
    }

    [Fact]
    public void Enrollment_response_contract_serializes_without_json_name_collisions()
    {
        var businessGlobalId = Guid.NewGuid();
        var branchGlobalId = Guid.NewGuid();
        var deviceGlobalId = Guid.NewGuid();
        var userGlobalId = Guid.NewGuid();

        var auth = new AuthResponse(
            "access-token",
            "refresh-token",
            DateTimeOffset.UtcNow.AddMinutes(15),
            businessGlobalId,
            branchGlobalId,
            deviceGlobalId,
            "PointOfSale",
            userGlobalId,
            "Administrator");

        var response = new EnrolledAdministrativeDevice(
            businessGlobalId,
            "Business",
            1,
            branchGlobalId,
            "Main",
            1,
            deviceGlobalId,
            "Tablet",
            "PointOfSale",
            1,
            userGlobalId,
            "Administrator Name",
            "admin",
            "Administrator",
            1,
            auth);

        var json = JsonSerializer.Serialize(
            response,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        using var document = JsonDocument.Parse(json);

        var root = document.RootElement;

        Assert.Equal(
            "Administrator Name",
            root.GetProperty("userDisplayName").GetString());

        Assert.Equal(
            "admin",
            root.GetProperty("username").GetString());

        Assert.Equal(
            "Administrator Name",
            root.GetProperty("user").GetProperty("name").GetString());

        Assert.Equal(
            "admin",
            root.GetProperty("user").GetProperty("username").GetString());
    }
}