using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class CashMovementReportTests
{
    [Fact]
    public async Task Central_cash_report_includes_manual_in_and_out_and_is_tenant_scoped()
    {
        await using var test=await SqlServerTestDatabase.CreateAsync(); var now=DateTimeOffset.UtcNow;
        var tenant=await test.SeedTenantAsync("CashReportA"); var foreign=await test.SeedTenantAsync("CashReportB");
        var own=await AddSessionAsync(test,tenant,now.AddHours(-1),1000); var other=await AddSessionAsync(test,foreign,now.AddHours(-1),9000);
        test.Db.CashMovements.AddRange(
            new CashMovement{GlobalId=Guid.NewGuid(),BusinessId=tenant.Business.Id,CashSessionId=own.Id,UserId=tenant.User.Id,MovementDate=now.AddMinutes(-30),Type="ManualIn",AmountCents=500,Notes="Fondo"},
            new CashMovement{GlobalId=Guid.NewGuid(),BusinessId=tenant.Business.Id,CashSessionId=own.Id,UserId=tenant.User.Id,MovementDate=now.AddMinutes(-20),Type="ManualOut",AmountCents=-200,Notes="Retiro"},
            new CashMovement{GlobalId=Guid.NewGuid(),BusinessId=foreign.Business.Id,CashSessionId=other.Id,UserId=foreign.User.Id,MovementDate=now.AddMinutes(-10),Type="ManualIn",AmountCents=50000,Notes="Foreign"});
        await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var result=await new RemoteReportService(test.Db).CashAsync(Context(tenant),new ReportPeriod(now.AddDays(-1),now.AddDays(1)),1,50,TestContext.Current.CancellationToken);
        var row=Assert.Single(result.Items); Assert.Equal(1000,row.OpeningBalanceCents); Assert.Equal(500,row.ManualInCents); Assert.Equal(200,row.ManualOutCents); Assert.Equal(1300,row.CalculatedExpectedCashCents);
    }

    private static async Task<CashSession> AddSessionAsync(SqlServerTestDatabase test,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,DateTimeOffset openedAt,long opening)
    {
        var session=new CashSession{GlobalId=Guid.NewGuid(),BusinessId=tenant.Business.Id,BranchId=tenant.Branch.Id,DeviceId=tenant.Device.Id,UserId=tenant.User.Id,OpenedAt=openedAt,OpeningBalanceCents=opening,Status="Open",UpdatedAt=DateTimeOffset.UtcNow};
        test.Db.CashSessions.Add(session); await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken); return session;
    }

    private static SyncTenantContext Context((Business Business,Branch Branch,Device Device,UserAccount User) tenant)=>new(tenant.Business.Id,tenant.Business.GlobalId,tenant.Branch.Id,tenant.Branch.GlobalId,tenant.Device.Id,tenant.Device.GlobalId,tenant.User.Id,tenant.User.GlobalId,tenant.User.Role,tenant.Device.Mode);
}
