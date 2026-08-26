using Pos.Application;
namespace Pos.Infrastructure.Tests;
public sealed class FakeTokenService : ITokenService
{
    public Task<AuthResponse?> LoginAsync(LoginRequest request,CancellationToken cancellationToken)=>Task.FromResult<AuthResponse?>(new AuthResponse("test-access-token","test-refresh-token",DateTimeOffset.UtcNow.AddMinutes(30),request.BusinessGlobalId,Guid.Empty,request.DeviceGlobalId,"AdminReadOnly",Guid.Empty,"Administrator"));
    public Task<AuthResponse?> RefreshAsync(RefreshRequest request,CancellationToken cancellationToken)=>Task.FromResult<AuthResponse?>(null);
}
