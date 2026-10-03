using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class InternalPosAdminTenantResolverTests
{
    [Fact]
    public async Task Resolves_only_requested_active_business()
    {
        await using var test = await TestDatabase.CreateAsync();

        var expected = await test.SeedTenantAsync(
            "INTERNAL-POS-ADMIN",
            role: "Administrator",
            mode: "AdminReadOnly");

        var foreign = await test.SeedTenantAsync(
            "FOREIGN",
            role: "Administrator",
            mode: "AdminReadOnly");

        var resolver = new InternalPosAdminTenantResolver(test.Db);

        var result = await resolver.ResolveAsync(
            expected.Business.GlobalId,
            CancellationToken.None);

        Assert.NotNull(result);
        Assert.Equal(expected.Business.Id, result!.BusinessId);
        Assert.Equal(expected.Business.GlobalId, result.BusinessGlobalId);
        Assert.Equal(expected.Branch.Id, result.BranchId);
        Assert.Equal(expected.Device.Id, result.DeviceId);
        Assert.Equal(expected.User.Id, result.UserId);

        Assert.NotEqual(foreign.Business.Id, result.BusinessId);
    }

    [Fact]
    public async Task Unknown_business_fails_closed()
    {
        await using var test = await TestDatabase.CreateAsync();
        await test.SeedTenantAsync(
            "KNOWN",
            role: "Administrator",
            mode: "AdminReadOnly");

        var result = await new InternalPosAdminTenantResolver(test.Db)
            .ResolveAsync(Guid.NewGuid(), CancellationToken.None);

        Assert.Null(result);
    }

    [Fact]
    public async Task Business_without_active_administrator_fails_closed()
    {
        await using var test = await TestDatabase.CreateAsync();

        var tenant = await test.SeedTenantAsync(
            "NO-ADMIN",
            role: "Seller",
            mode: "PointOfSale");

        var result = await new InternalPosAdminTenantResolver(test.Db)
            .ResolveAsync(
                tenant.Business.GlobalId,
                CancellationToken.None);

        Assert.Null(result);
    }
}
