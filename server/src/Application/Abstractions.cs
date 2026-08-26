namespace Pos.Application;

public interface ISyncService
{
    Task<SyncPushResponse> PushAsync(SyncPushRequest request, SyncTenantContext tenant, CancellationToken cancellationToken);
    Task<SyncPullResponse> PullAsync(long after, int take, SyncTenantContext tenant, CancellationToken cancellationToken);
}

public interface ITokenService
{
    Task<AuthResponse?> LoginAsync(LoginRequest request, CancellationToken cancellationToken);
    Task<AuthResponse?> RefreshAsync(RefreshRequest request, CancellationToken cancellationToken);
}
