namespace Pos.Domain;

public sealed class CentralInventoryTransferApplication
{
    public long Id { get; set; }

    public Guid GlobalId { get; set; }

    public Guid TransferGlobalId { get; set; }

    public long BusinessId { get; set; }

    public long BranchId { get; set; }

    public long DeviceId { get; set; }

    public DateTimeOffset AppliedAt { get; set; }

    public DateTimeOffset AcknowledgedAt { get; set; }
}