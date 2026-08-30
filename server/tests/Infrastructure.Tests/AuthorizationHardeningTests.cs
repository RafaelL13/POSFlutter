using System.Security.Claims;
using System.Text.Json;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class AuthorizationHardeningTests
{
    [Theory]
    [InlineData("UnknownRole")]
    [InlineData("")]
    [InlineData("administrator")]
    [InlineData("Manager ")]
    public void Unknown_or_malformed_roles_fail_closed(string role)
    {
        foreach (var capability in Enum.GetValues<BackendReadCapability>())
        {
            Assert.Equal(
                BackendReadPermission.None,
                BackendReadAuthorization.PermissionFor(role, "PointOfSale", capability));
        }
    }

    [Theory]
    [InlineData("UnknownMode")]
    [InlineData("")]
    [InlineData("pointofsale")]
    [InlineData("AdminReadOnly ")]
    public void Unknown_or_malformed_device_modes_fail_closed(string mode)
    {
        foreach (var capability in Enum.GetValues<BackendReadCapability>())
        {
            Assert.Equal(
                BackendReadPermission.None,
                BackendReadAuthorization.PermissionFor("Administrator", mode, capability));
        }
    }

    [Theory]
    [InlineData("Seller", BackendReadCapability.SalesRead, BackendReadPermission.OwnOnly)]
    [InlineData("Seller", BackendReadCapability.CashRead, BackendReadPermission.OwnOnly)]
    [InlineData("Supervisor", BackendReadCapability.SalesRead, BackendReadPermission.Branch)]
    [InlineData("Supervisor", BackendReadCapability.UsersRead, BackendReadPermission.None)]
    public void Critical_read_scope_matrix_is_explicit(
        string role,
        BackendReadCapability capability,
        BackendReadPermission expected)
    {
        Assert.Equal(
            expected,
            BackendReadAuthorization.PermissionFor(role, "PointOfSale", capability));
    }

    [Fact]
    public async Task Transactional_payload_cannot_impersonate_another_tenant_user()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Actor", role: "Administrator");
        var other = new UserAccount
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = tenant.Business.Id,
            Name = "Other User",
            Username = $"other-{Guid.NewGuid():N}",
            PasswordHash = "hash",
            PasswordSalt = "salt",
            Role = "Seller",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        test.Db.Users.Add(other);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);

        var entityId = Guid.NewGuid();
        using var payload = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            globalId = entityId,
            businessGlobalId = tenant.Business.GlobalId,
            branchGlobalId = tenant.Branch.GlobalId,
            deviceGlobalId = tenant.Device.GlobalId,
            userGlobalId = other.GlobalId,
            date = DateTimeOffset.UtcNow,
            concept = "Impersonated expense",
            category = "Security",
            amountCents = 100L,
            paymentMethod = "Cash",
            notes = (string?)null
        }));

        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            new SyncService(test.Db).PushAsync(
                new SyncPushRequest([
                    new SyncOperationDto(
                        Guid.NewGuid(),
                        "Expense",
                        entityId,
                        "Create",
                        1,
                        payload.RootElement.Clone())
                ]),
                Context(tenant),
                TestContext.Current.CancellationToken));

        Assert.Empty(test.Db.Expenses);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Forged_authorization_metadata_does_not_bypass_role_policy()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Metadata", role: "Seller");
        using var payload = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            authorizedBy = Guid.NewGuid(),
            performedBy = tenant.User.GlobalId,
            role = "Administrator"
        }));
        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([
                new SyncOperationDto(
                    Guid.NewGuid(),
                    "Purchase",
                    Guid.NewGuid(),
                    "Create",
                    1,
                    payload.RootElement.Clone())
            ]),
            Context(tenant),
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);
        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.RoleDenied, result.ErrorCode);
        Assert.Empty(test.Db.Purchases);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public void Missing_tenant_claim_fails_closed()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity([
            new Claim("business_id", "1")
        ], "test"));

        Assert.Throws<UnauthorizedAccessException>(() => TenantClaims.Require(principal));
    }

    [Fact]
    public void Malformed_tenant_claim_never_creates_context()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity([
            new Claim("business_id", "not-a-number"),
            new Claim("business_gid", Guid.NewGuid().ToString()),
            new Claim("branch_id", "1"),
            new Claim("branch_gid", Guid.NewGuid().ToString()),
            new Claim("device_id", "1"),
            new Claim("device_gid", Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.NameIdentifier, "1"),
            new Claim("user_gid", Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.Role, "Administrator"),
            new Claim("device_mode", "PointOfSale")
        ], "test"));

        Assert.Throws<UnauthorizedAccessException>(() => TenantClaims.Require(principal));
    }

    private static SyncTenantContext Context(
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant) =>
        new(
            tenant.Business.Id,
            tenant.Business.GlobalId,
            tenant.Branch.Id,
            tenant.Branch.GlobalId,
            tenant.Device.Id,
            tenant.Device.GlobalId,
            tenant.User.Id,
            tenant.User.GlobalId,
            tenant.User.Role,
            tenant.Device.Mode);
}
