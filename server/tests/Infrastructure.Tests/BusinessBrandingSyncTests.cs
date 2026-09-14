using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

public sealed class BusinessBrandingSyncTests
{
    [Fact]
    public async Task Branding_update_persists_and_repeated_operation_is_idempotent()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync("Brand");
        var service = new SyncService(t.Db);
        var context = Context(tenant);
        var operationId = Guid.NewGuid();
        var logo = new byte[] { 0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10 };
        var request = Request(operationId, tenant.Business, "Mi Tienda", logo, "image/png");

        var first = await service.PushAsync(request, context, TestContext.Current.CancellationToken);
        var second = await service.PushAsync(request, context, TestContext.Current.CancellationToken);

        Assert.Equal("Applied", first.Results.Single().Status);
        Assert.Equal("AlreadyProcessed", second.Results.Single().Status);
        var business = await t.Db.Businesses.SingleAsync(TestContext.Current.CancellationToken);
        Assert.Equal("Mi Tienda", business.DisplayName);
        Assert.Equal(logo, business.LogoBlob);
        Assert.Equal("image/png", business.LogoMimeType);
        Assert.Equal(0x1565c0, business.PrimaryColor);
        var pull = await service.PullAsync(0, 100, context, TestContext.Current.CancellationToken);
        var payload = pull.Changes.Single(x => x.EntityType == "Business").Payload;
        Assert.Equal("Mi Tienda", payload.GetProperty("displayName").GetString());
        Assert.Equal("image/png", payload.GetProperty("logoMimeType").GetString());
    }

    [Fact]
    public async Task Branding_update_can_remove_logo()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync("Remove");
        tenant.Business.LogoBlob = new byte[] { 1 };
        tenant.Business.LogoMimeType = "image/png";
        await t.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var result = await new SyncService(t.Db).PushAsync(
            Request(Guid.NewGuid(), tenant.Business, "Sin logo", null, null),
            Context(tenant), TestContext.Current.CancellationToken);
        Assert.Equal("Applied", result.Results.Single().Status);
        Assert.Null(tenant.Business.LogoBlob);
        Assert.Null(tenant.Business.LogoMimeType);
    }

    [Fact]
    public async Task Old_payload_preserves_existing_branding()
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync("Old");
        tenant.Business.DisplayName = "Existing";
        tenant.Business.BrandingUpdatedAt = DateTimeOffset.UtcNow;
        await t.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(new {
            globalId = tenant.Business.GlobalId, name = "Renamed", active = true,
            updatedAt = DateTimeOffset.UtcNow, baseServerVersion = tenant.Business.ServerVersion
        }));
        var operation = new SyncOperationDto(Guid.NewGuid(), "Business", tenant.Business.GlobalId, "Update", 1, document.RootElement.Clone());
        var result = await new SyncService(t.Db).PushAsync(new SyncPushRequest([operation]), Context(tenant), TestContext.Current.CancellationToken);
        Assert.Equal("Applied", result.Results.Single().Status);
        Assert.Equal("Existing", tenant.Business.DisplayName);
    }

    [Theory]
    [InlineData("image/gif", false)]
    [InlineData("image/png", true)]
    public async Task Invalid_branding_is_rejected(string mime, bool oversized)
    {
        await using var t = await TestDatabase.CreateAsync();
        var tenant = await t.SeedTenantAsync("Invalid");
        var logo = oversized ? new byte[262145] : new byte[] { 1, 2, 3, 4 };
        var result = await new SyncService(t.Db).PushAsync(
            Request(Guid.NewGuid(), tenant.Business, "Invalid", logo, mime),
            Context(tenant), TestContext.Current.CancellationToken);
        Assert.Equal("Rejected", result.Results.Single().Status);
        Assert.Null(tenant.Business.DisplayName);
    }

    private static SyncPushRequest Request(Guid operationId, Pos.Domain.Business business, string displayName, byte[]? logo, string? mime)
    {
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(new {
            globalId = business.GlobalId, name = business.Name, active = true,
            updatedAt = DateTimeOffset.UtcNow, baseServerVersion = business.ServerVersion,
            displayName, logoBase64 = logo, logoMimeType = mime,
            primaryColor = 0x1565c0, brandingUpdatedAt = DateTimeOffset.UtcNow
        }));
        return new SyncPushRequest([new SyncOperationDto(operationId, "Business", business.GlobalId, "Update", 1, document.RootElement.Clone())]);
    }

    private static SyncTenantContext Context((Pos.Domain.Business Business, Pos.Domain.Branch Branch, Pos.Domain.Device Device, Pos.Domain.UserAccount User) t) =>
        new(t.Business.Id, t.Business.GlobalId, t.Branch.Id, t.Branch.GlobalId, t.Device.Id, t.Device.GlobalId, t.User.Id, t.User.GlobalId, t.User.Role, t.Device.Mode);
}
