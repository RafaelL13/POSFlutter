using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class CentralInventoryTransferApplicationSyncTests
{
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task Ack_creates_application_for_authenticated_device()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK");

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var applicationGlobalId = Guid.NewGuid();

        var result = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                applicationGlobalId,
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        Assert.Equal("Applied", result.Status);

        var application =
            await test.Db.CentralInventoryTransferApplications
                .SingleAsync(
                    x => x.GlobalId == applicationGlobalId,
                    TestContext.Current.CancellationToken);

        Assert.Equal(
            transferGlobalId,
            application.TransferGlobalId);

        Assert.Equal(
            tenant.Business.Id,
            application.BusinessId);

        Assert.Equal(
            tenant.Branch.Id,
            application.BranchId);

        Assert.Equal(
            tenant.Device.Id,
            application.DeviceId);

        Assert.NotEqual(
            default,
            application.AppliedAt);

        Assert.NotEqual(
            default,
            application.AcknowledgedAt);
    }

    [Fact]
    public async Task Exact_retry_is_already_processed()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK-EXACT");

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var operation = BuildOperation(
            Guid.NewGuid(),
            Guid.NewGuid(),
            transferGlobalId,
            tenant.Business.GlobalId,
            tenant.Branch.GlobalId,
            tenant.Device.GlobalId);

        var first = await PushAsync(
            test,
            tenant,
            operation);

        var second = await PushAsync(
            test,
            tenant,
            operation);

        Assert.Equal("Applied", first.Status);
        Assert.Equal("AlreadyProcessed", second.Status);

        var applications =
            await test.Db.CentralInventoryTransferApplications
                .Where(
                    x =>
                        x.BusinessId == tenant.Business.Id &&
                        x.TransferGlobalId == transferGlobalId &&
                        x.DeviceId == tenant.Device.Id)
                .ToListAsync(TestContext.Current.CancellationToken);

        Assert.Single(applications);
    }

    [Fact]
    public async Task Logical_retry_with_new_operation_is_idempotent_per_device()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK-LOGICAL");

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var first = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        var second = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        Assert.Equal("Applied", first.Status);
        Assert.Equal("Applied", second.Status);

        var applications =
            await test.Db.CentralInventoryTransferApplications
                .Where(
                    x =>
                        x.BusinessId == tenant.Business.Id &&
                        x.TransferGlobalId == transferGlobalId &&
                        x.DeviceId == tenant.Device.Id)
                .ToListAsync(TestContext.Current.CancellationToken);

        Assert.Single(applications);
    }

    [Fact]
    public async Task Ack_rejects_device_identity_mismatch_without_persistence()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK-DEVICE");

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var result = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                Guid.NewGuid()));

        Assert.Equal("Rejected", result.Status);

        Assert.Empty(
            await test.Db.CentralInventoryTransferApplications
                .ToListAsync(TestContext.Current.CancellationToken));

        Assert.Empty(
            await test.Db.InboundOperations
                .ToListAsync(TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Ack_rejects_unknown_transfer_without_persistence()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK-MISSING");

        var result = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                Guid.NewGuid(),
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        Assert.Equal("Rejected", result.Status);

        Assert.Empty(
            await test.Db.CentralInventoryTransferApplications
                .ToListAsync(TestContext.Current.CancellationToken));

        Assert.Empty(
            await test.Db.InboundOperations
                .ToListAsync(TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Seller_can_transport_technical_ack()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CENTRAL-ACK-SELLER");

        tenant.User.Role = "Seller";

        await test.Db.SaveChangesAsync(
            TestContext.Current.CancellationToken);

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var result = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        Assert.Equal("Applied", result.Status);

        Assert.Single(
            await test.Db.CentralInventoryTransferApplications
                .Where(
                    x =>
                        x.BusinessId == tenant.Business.Id &&
                        x.TransferGlobalId == transferGlobalId &&
                        x.DeviceId == tenant.Device.Id)
                .ToListAsync(TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task AdminReadOnly_cannot_push_technical_ack()
    {
        await using var test = await TestDatabase.CreateAsync();

        var tenant = await test.SeedTenantAsync(
            "CENTRAL-ACK-READONLY",
            mode: "AdminReadOnly");

        var transferGlobalId = Guid.NewGuid();

        await AddReceiptAsync(
            test,
            tenant,
            transferGlobalId);

        var result = await PushAsync(
            test,
            tenant,
            BuildOperation(
                Guid.NewGuid(),
                Guid.NewGuid(),
                transferGlobalId,
                tenant.Business.GlobalId,
                tenant.Branch.GlobalId,
                tenant.Device.GlobalId));

        Assert.Equal("Rejected", result.Status);

        Assert.Empty(
            await test.Db.CentralInventoryTransferApplications
                .ToListAsync(TestContext.Current.CancellationToken));
    }

    private static async Task AddReceiptAsync(
        TestDatabase test,
        (
            Business Business,
            Branch Branch,
            Device Device,
            UserAccount User
        ) tenant,
        Guid transferGlobalId)
    {
        test.Db.CentralInventoryTransferReceipts.Add(
            new CentralInventoryTransferReceipt
            {
                TransferGlobalId = transferGlobalId,
                BusinessId = tenant.Business.Id,
                BranchId = tenant.Branch.Id,
                ReceivedAt = DateTimeOffset.UtcNow
            });

        await test.Db.SaveChangesAsync(
            TestContext.Current.CancellationToken);
    }

    private static SyncOperationDto BuildOperation(
        Guid operationGlobalId,
        Guid applicationGlobalId,
        Guid transferGlobalId,
        Guid businessGlobalId,
        Guid branchGlobalId,
        Guid deviceGlobalId)
    {
        var payload =
            new CentralTransferAppliedSyncPayload(
                applicationGlobalId,
                transferGlobalId,
                businessGlobalId,
                branchGlobalId,
                deviceGlobalId,
                DateTimeOffset.UtcNow);

        using var document =
            JsonDocument.Parse(
                JsonSerializer.Serialize(
                    payload,
                    JsonOptions));

        return new SyncOperationDto(
            operationGlobalId,
            "CentralTransferApplied",
            applicationGlobalId,
            "Create",
            1,
            document.RootElement.Clone());
    }

    private static async Task<SyncOperationResult> PushAsync(
        TestDatabase test,
        (
            Business Business,
            Branch Branch,
            Device Device,
            UserAccount User
        ) tenant,
        SyncOperationDto operation)
    {
        var context =
            new SyncTenantContext(
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

        var response =
            await new SyncService(test.Db).PushAsync(
                new SyncPushRequest([operation]),
                context,
                TestContext.Current.CancellationToken);

        return Assert.Single(response.Results);
    }
}