namespace Pos.Application;

public sealed record CentralTransferAppliedSyncPayload(
    Guid GlobalId,
    Guid TransferGlobalId,
    Guid BusinessGlobalId,
    Guid BranchGlobalId,
    Guid DeviceGlobalId,
    DateTimeOffset AppliedAt);