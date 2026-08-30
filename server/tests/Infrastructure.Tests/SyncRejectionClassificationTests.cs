using System.Text.Json;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class SyncRejectionClassificationTests
{
    [Fact]
    public async Task Device_read_only_returns_structured_authorization_rejection()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("DeviceReadOnly", mode: "AdminReadOnly");
        var result = await PushAsync(test, tenant, "Sale", "Create", "{}");

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.DeviceReadOnly, result.ErrorCode);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Role_denied_returns_structured_authorization_rejection()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("RoleDenied", role: "Seller");
        var result = await PushAsync(test, tenant, "Category", "Create", "{}");

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.RoleDenied, result.ErrorCode);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Invalid_payload_returns_validation_code()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Validation");
        var result = await PushAsync(test, tenant, "Category", "Create", "{}");

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.ValidationFailed, result.ErrorCode);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Unsupported_operation_returns_terminal_code()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("Unsupported");
        var result = await PushAsync(test, tenant, "Unknown", "Create", "{}");

        Assert.Equal("Rejected", result.Status);
        Assert.Equal(SyncErrorCodes.UnsupportedOperation, result.ErrorCode);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Changed_role_rejects_stale_authenticated_context_without_mutation()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("ChangedRole", role: "Manager");
        var stale = Context(tenant);
        tenant.User.Role = "Seller";
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        using var payload = JsonDocument.Parse("{}");
        var request = new SyncPushRequest([
            new SyncOperationDto(
                Guid.NewGuid(),
                "Category",
                Guid.NewGuid(),
                "Create",
                1,
                payload.RootElement.Clone())
        ]);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            new SyncService(test.Db).PushAsync(request, stale, TestContext.Current.CancellationToken));
        Assert.Empty(test.Db.InboundOperations);
    }

    private static async Task<SyncOperationResult> PushAsync(
        TestDatabase test,
        (Business Business, Branch Branch, Device Device, UserAccount User) tenant,
        string entityType,
        string operation,
        string json)
    {
        using var payload = JsonDocument.Parse(json);
        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([
                new SyncOperationDto(
                    Guid.NewGuid(),
                    entityType,
                    Guid.NewGuid(),
                    operation,
                    1,
                    payload.RootElement.Clone())
            ]),
            Context(tenant),
            TestContext.Current.CancellationToken);
        return Assert.Single(response.Results);
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
