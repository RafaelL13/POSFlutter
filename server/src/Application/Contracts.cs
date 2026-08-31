using System.Text.Json;

namespace Pos.Application;

public sealed record SyncTenantContext(long BusinessId, Guid BusinessGlobalId, long BranchId, Guid BranchGlobalId, long DeviceId, Guid DeviceGlobalId, long UserId, Guid UserGlobalId, string Role, string DeviceMode);
public sealed record SyncOperationDto(Guid GlobalId,string EntityType,Guid EntityGlobalId,string Operation,int PayloadVersion,JsonElement Payload);
public sealed record SyncPushRequest(IReadOnlyList<SyncOperationDto> Operations);
public sealed record SyncOperationResult(Guid GlobalId,string Status,string? Error=null,long? RemoteVersion=null,JsonElement? RemotePayload=null,string? ErrorCode=null);
public sealed record SyncPushResponse(IReadOnlyList<SyncOperationResult> Results,DateTimeOffset ServerTime);
public sealed record SyncPullChange(long Cursor,string EntityType,Guid EntityGlobalId,string Operation,long Version,DateTimeOffset ChangedAt,JsonElement Payload);
public sealed record SyncPullResponse(long NextCursor,bool HasMore,IReadOnlyList<SyncPullChange> Changes,DateTimeOffset ServerTime);

public static class SyncErrorCodes
{
    public const string AuthorizationDenied = "AuthorizationDenied";
    public const string DeviceReadOnly = "DeviceReadOnly";
    public const string RoleDenied = "RoleDenied";
    public const string ValidationFailed = "ValidationFailed";
    public const string Conflict = "Conflict";
    public const string UnsupportedOperation = "UnsupportedOperation";
    public const string ServerError = "ServerError";
}

public sealed record LoginRequest(Guid BusinessGlobalId,Guid DeviceGlobalId,string Username,string Password);
public sealed record RefreshRequest(string RefreshToken);
public sealed record AuthResponse(string AccessToken,string RefreshToken,DateTimeOffset AccessTokenExpiresAt,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,string DeviceMode,Guid UserGlobalId,string Role);
public sealed record BootstrapRequest(Guid BusinessGlobalId,string BusinessName,Guid BranchGlobalId,string BranchName,Guid DeviceGlobalId,string DeviceName,Guid UserGlobalId,string UserDisplayName,string Username,string PasswordHash,string PasswordSalt);
public sealed record CreateDeviceEnrollmentRequest(int? ExpiresInMinutes);
public sealed record RedeemDeviceEnrollmentRequest(string Token,string Username,string Password,string DeviceName,Guid DeviceGlobalId);
public sealed record DeviceEnrollmentInvitation(string Code,Guid BusinessGlobalId,Guid BranchGlobalId,DateTimeOffset ExpiresAt);
public sealed record EnrollmentBusiness(Guid GlobalId,string Name,long ServerVersion);
public sealed record EnrollmentBranch(Guid GlobalId,string Name,long ServerVersion);
public sealed record EnrollmentDevice(Guid GlobalId,string Name,string Mode,long ServerVersion);
public sealed record EnrollmentUser(Guid GlobalId,string Name,string Username,string Role,long ServerVersion);
public sealed record EnrolledAdministrativeDevice(Guid BusinessGlobalId,string BusinessName,long BusinessServerVersion,Guid BranchGlobalId,string BranchName,long BranchServerVersion,Guid DeviceGlobalId,string DeviceName,string DeviceMode,long DeviceServerVersion,Guid UserGlobalId,string UserName,string Username,string Role,long UserServerVersion,AuthResponse Auth)
{
    public EnrollmentBusiness Business => new(BusinessGlobalId,BusinessName,BusinessServerVersion);
    public EnrollmentBranch Branch => new(BranchGlobalId,BranchName,BranchServerVersion);
    public EnrollmentDevice Device => new(DeviceGlobalId,DeviceName,DeviceMode,DeviceServerVersion);
    public EnrollmentUser User => new(UserGlobalId,UserName,Username,Role,UserServerVersion);
}

public sealed record BusinessSyncPayload(Guid GlobalId,string Name,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record BranchSyncPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record DeviceSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,string Name,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record UserSyncPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string Username,string PasswordHash,string PasswordSalt,string Role,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record CategorySyncPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string? Description,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record SupplierSyncPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string? ContactName,string? Phone,string? Email,string? Address,string? Notes,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);
public sealed record ProductSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid? CategoryGlobalId,string Code,string? Barcode,string Name,string Presentation,long SalePriceCents,int MinimumStock,bool Active,DateTimeOffset UpdatedAt,long? BaseServerVersion=null);

public sealed record PurchaseLineSyncPayload(Guid DetailGlobalId,Guid ProductGlobalId,int Quantity,long UnitCostCents,long SubtotalCents,Guid LotGlobalId);
public sealed record PurchaseSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,Guid UserGlobalId,Guid SupplierGlobalId,DateTimeOffset Date,string? Reference,string? Notes,long TotalCents,IReadOnlyList<PurchaseLineSyncPayload> Lines);
public sealed record InventoryLotAllocationPayload(Guid LotGlobalId,int Quantity,long UnitCostCents);
public sealed record InventoryAdjustmentSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,Guid UserGlobalId,Guid ProductGlobalId,DateTimeOffset Date,string Type,int QuantityDelta,string Reason,Guid? NewLotGlobalId,long? UnitCostCents,IReadOnlyList<InventoryLotAllocationPayload> Allocations);
public sealed record ExpenseSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,Guid UserGlobalId,DateTimeOffset Date,string Concept,string? Category,long AmountCents,string PaymentMethod,string? Notes);
public sealed record CashSessionSyncPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,Guid UserGlobalId,DateTimeOffset OpenedAt,long OpeningBalanceCents,string Status,DateTimeOffset? ClosedAt,long? CountedCashCents,long? ExpectedCashCents,long? DifferenceCents);
public sealed record SaleLotSyncPayload(Guid GlobalId,Guid LotGlobalId,int Quantity,long UnitCostCents,long TotalCostCents);
public sealed record SaleLineSyncPayload(Guid DetailGlobalId,Guid ProductGlobalId,int Quantity,long UnitPriceCents,long TotalCents,long FifoCostCents,IReadOnlyList<SaleLotSyncPayload> Lots);
public sealed record SaleSyncPayload(Guid GlobalId,Guid IdempotencyKey,Guid BusinessGlobalId,Guid BranchGlobalId,Guid DeviceGlobalId,Guid UserGlobalId,string Folio,DateTimeOffset SaleDateTime,long SubtotalCents,long DiscountCents,long TotalCents,long FifoCostCents,long GrossProfitCents,string PaymentMethod,long? ReceivedCents,long ChangeCents,IReadOnlyList<SaleLineSyncPayload> Lines);
public sealed record SaleCancelSyncPayload(Guid GlobalId,Guid DeviceGlobalId,Guid UserGlobalId,DateTimeOffset CancelledAt,string Reason);

public sealed record BusinessPullPayload(Guid GlobalId,string Name,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
public sealed record BranchPullPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
public sealed record DevicePullPayload(Guid GlobalId,Guid BusinessGlobalId,Guid BranchGlobalId,string Name,string Mode,bool Active,DateTimeOffset? LastSyncAt,long ServerVersion);
public sealed record UserPullPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string Username,string PasswordHash,string PasswordSalt,string Role,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
public sealed record CategoryPullPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string? Description,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
public sealed record SupplierPullPayload(Guid GlobalId,Guid BusinessGlobalId,string Name,string? ContactName,string? Phone,string? Email,string? Address,string? Notes,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
public sealed record ProductPullPayload(Guid GlobalId,Guid BusinessGlobalId,Guid? CategoryGlobalId,string Code,string? Barcode,string Name,string Presentation,long SalePriceCents,int MinimumStock,bool Active,DateTimeOffset UpdatedAt,long ServerVersion);
