using System.Text.Json;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class ExpenseCashSessionSyncTests
{
    [Fact]
    public async Task Cash_expense_is_linked_to_its_authenticated_device_session()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("ExpenseLink");
        var session = await AddSessionAsync(test, tenant);
        var result = await PushAsync(test, tenant, Operation(tenant, Guid.NewGuid(), "Cash", session.GlobalId));

        Assert.Equal("Applied", result.Status);
        Assert.Equal(session.Id, Assert.Single(test.Db.Expenses).CashSessionId);
    }

    [Fact]
    public async Task Cash_expense_cannot_link_a_session_from_another_device()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("ExpenseWrongDevice");
        var other = await test.SeedTenantAsync("ExpenseOtherDevice");
        var session = await AddSessionAsync(test, other);
        var result = await PushAsync(test, tenant, Operation(tenant, Guid.NewGuid(), "Cash", session.GlobalId));

        Assert.Equal("Retry", result.Status);
        Assert.Empty(test.Db.Expenses);
        Assert.Empty(test.Db.InboundOperations);
    }

    [Fact]
    public async Task Legacy_cash_expense_without_session_link_remains_unlinked()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("ExpenseLegacy");
        var result = await PushAsync(test, tenant, Operation(tenant, Guid.NewGuid(), "Cash"));

        Assert.Equal("Applied", result.Status);
        Assert.Null(Assert.Single(test.Db.Expenses).CashSessionId);
    }

    private static async Task<CashSession> AddSessionAsync(TestDatabase test, (Business Business, Branch Branch, Device Device, UserAccount User) tenant)
    {
        var session = new CashSession { GlobalId = Guid.NewGuid(), BusinessId = tenant.Business.Id, BranchId = tenant.Branch.Id, DeviceId = tenant.Device.Id, UserId = tenant.User.Id, OpenedAt = DateTimeOffset.UtcNow.AddMinutes(-5), Status = "Open", UpdatedAt = DateTimeOffset.UtcNow };
        test.Db.CashSessions.Add(session);
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return session;
    }

    private static SyncOperationDto Operation((Business Business, Branch Branch, Device Device, UserAccount User) tenant, Guid expenseGlobalId, string paymentMethod, Guid? cashSessionGlobalId = null)
    {
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(new { globalId = expenseGlobalId, businessGlobalId = tenant.Business.GlobalId, branchGlobalId = tenant.Branch.GlobalId, deviceGlobalId = tenant.Device.GlobalId, userGlobalId = tenant.User.GlobalId, date = DateTimeOffset.UtcNow, concept = "Flete", amountCents = 250, paymentMethod, cashSessionGlobalId }));
        return new SyncOperationDto(Guid.NewGuid(), "Expense", expenseGlobalId, "Create", 1, document.RootElement.Clone());
    }

    private static async Task<SyncOperationResult> PushAsync(TestDatabase test, (Business Business, Branch Branch, Device Device, UserAccount User) tenant, SyncOperationDto operation) => Assert.Single((await new SyncService(test.Db).PushAsync(new SyncPushRequest([operation]), new SyncTenantContext(tenant.Business.Id, tenant.Business.GlobalId, tenant.Branch.Id, tenant.Branch.GlobalId, tenant.Device.Id, tenant.Device.GlobalId, tenant.User.Id, tenant.User.GlobalId, tenant.User.Role, tenant.Device.Mode), TestContext.Current.CancellationToken)).Results);
}