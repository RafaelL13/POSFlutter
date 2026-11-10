using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Pos.Application;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

public sealed class JwtTokenServiceValidationTests
{
    [Fact]
    public async Task Incomplete_login_request_is_rejected_without_creating_a_refresh_token()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("LOGIN-VALIDATION");
        var service = new TokenService(
            test.Db,
            Options.Create(new JwtOptions { SigningKey = "lab-only-test-signing-key-must-be-long-enough" }));

        var response = await service.LoginAsync(
            new LoginRequest(tenant.Business.GlobalId, tenant.Device.GlobalId, "adminLOGIN-VALIDATION", null!),
            TestContext.Current.CancellationToken);

        Assert.Null(response);
        Assert.False(await test.Db.RefreshTokens.AnyAsync(TestContext.Current.CancellationToken));
    }
}
