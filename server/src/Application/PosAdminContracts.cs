namespace Pos.Application;

public sealed record PosAdminDeviceSyncRow(
    Guid DeviceGlobalId,
    Guid BranchGlobalId,
    string BranchName,
    string DeviceName,
    string Mode,
    bool Active,
    DateTimeOffset? LastSyncAt,
    int? AgeMinutes,
    string Freshness);

public sealed record PosAdminSyncOverview(
    DateTimeOffset GeneratedAt,
    int TotalDevices,
    int CurrentDevices,
    int DelayedDevices,
    int StaleDevices,
    int NeverSyncedDevices,
    IReadOnlyList<PosAdminDeviceSyncRow> Devices);

public sealed record BranchPerformanceRow(
    Guid BranchGlobalId,
    string BranchName,
    int SalesCount,
    int Units,
    long NetSalesCents,
    long FifoCostCents,
    long GrossProfitCents,
    double GrossMarginPercent,
    int CancelledSalesCount,
    long CancelledSalesCents);
