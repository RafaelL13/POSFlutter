using System.Text.Json;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class CashMovementSyncTests
{
    [Fact]
    public async Task Manager_manual_in_is_applied_and_operation_retry_is_idempotent()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("CashIn", role: "Manager");
        var session = await AddSessionAsync(test, tenant);
        var movementId = Guid.NewGuid();
        var operationId = Guid.NewGuid();
        var operation = Operation(operationId,movementId,tenant,session.GlobalId,"ManualIn",500,DateTimeOffset.UtcNow,"Fondo adicional");
        var service = new SyncService(test.Db);
        var first = await service.PushAsync(new SyncPushRequest([operation]),Context(tenant),TestContext.Current.CancellationToken);
        var second = await service.PushAsync(new SyncPushRequest([operation]),Context(tenant),TestContext.Current.CancellationToken);
        Assert.Equal("Applied",Assert.Single(first.Results).Status);
        Assert.Equal("AlreadyProcessed",Assert.Single(second.Results).Status);
        var movement = Assert.Single(test.Db.CashMovements.Where(x=>x.GlobalId==movementId));
        Assert.Equal("ManualIn",movement.Type); Assert.Equal(500,movement.AmountCents); Assert.Equal("Fondo adicional",movement.Notes);
    }

    [Fact]
    public async Task Invalid_manual_out_sign_is_rejected_without_persistence()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("BadSign",role:"Manager");
        var session = await AddSessionAsync(test,tenant); var movementId=Guid.NewGuid();
        var result = await PushAsync(test,tenant,Operation(Guid.NewGuid(),movementId,tenant,session.GlobalId,"ManualOut",100,DateTimeOffset.UtcNow,"Signo inválido"));
        Assert.Equal("Rejected",result.Status); Assert.Equal(SyncErrorCodes.ValidationFailed,result.ErrorCode);
        Assert.DoesNotContain(test.Db.CashMovements,x=>x.GlobalId==movementId);
    }

    [Fact]
    public async Task Seller_cannot_sync_manual_cash_movement()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("SellerCash",role:"Seller");
        var session = await AddSessionAsync(test,tenant); var movementId=Guid.NewGuid();
        var result = await PushAsync(test,tenant,Operation(Guid.NewGuid(),movementId,tenant,session.GlobalId,"ManualIn",100,DateTimeOffset.UtcNow,"No permitido"));
        Assert.Equal("Rejected",result.Status); Assert.Equal(SyncErrorCodes.RoleDenied,result.ErrorCode);
        Assert.DoesNotContain(test.Db.CashMovements,x=>x.GlobalId==movementId);
    }

    [Fact]
    public async Task Supervisor_manual_out_requires_second_user_authorization()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("SupervisorNoAuth",role:"Supervisor");
        var session = await AddSessionAsync(test,tenant); var movementId=Guid.NewGuid();
        var result = await PushAsync(test,tenant,Operation(Guid.NewGuid(),movementId,tenant,session.GlobalId,"ManualOut",-100,DateTimeOffset.UtcNow,"Retiro sin autorización"));
        Assert.Equal("Rejected",result.Status); Assert.Equal(SyncErrorCodes.RoleDenied,result.ErrorCode);
        Assert.DoesNotContain(test.Db.CashMovements,x=>x.GlobalId==movementId);
    }

    [Fact]
    public async Task Supervisor_manual_out_accepts_valid_manager_authorization()
    {
        await using var test = await TestDatabase.CreateAsync();
        var tenant = await test.SeedTenantAsync("SupervisorAuth",role:"Supervisor");
        var session = await AddSessionAsync(test,tenant);
        var manager = new UserAccount{GlobalId=Guid.NewGuid(),BusinessId=tenant.Business.Id,Name="Manager Authorizer",Username=$"manager-{Guid.NewGuid():N}",PasswordHash="hash",PasswordSalt="salt",Role="Manager",Active=true,CreatedAt=DateTimeOffset.UtcNow,UpdatedAt=DateTimeOffset.UtcNow};
        test.Db.Users.Add(manager); await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var movementId=Guid.NewGuid(); var now=DateTimeOffset.UtcNow;
        var authorization = new{authorizationGlobalId=Guid.NewGuid(),capability="cashWithdrawal",requirement="SecondUserAuthorization",performedByUserGlobalId=tenant.User.GlobalId,authorizedByUserGlobalId=manager.GlobalId,businessGlobalId=tenant.Business.GlobalId,deviceGlobalId=tenant.Device.GlobalId,reason="Retiro autorizado",authorizedAt=now.AddSeconds(-1),consumedAt=now,operation="ManualWithdrawal",entityType="CashMovement",entityGlobalId=movementId};
        var result = await PushAsync(test,tenant,Operation(Guid.NewGuid(),movementId,tenant,session.GlobalId,"ManualOut",-200,now,"Retiro autorizado",authorization));
        Assert.Equal("Applied",result.Status); var movement=Assert.Single(test.Db.CashMovements.Where(x=>x.GlobalId==movementId)); Assert.Equal(-200,movement.AmountCents);
    }

    [Fact]
    public async Task Missing_cash_session_is_retryable_and_does_not_commit_inbound_marker()
    {
        await using var test=await TestDatabase.CreateAsync(); var tenant=await test.SeedTenantAsync("MissingSession",role:"Manager"); var movementId=Guid.NewGuid();
        var result=await PushAsync(test,tenant,Operation(Guid.NewGuid(),movementId,tenant,Guid.NewGuid(),"ManualIn",100,DateTimeOffset.UtcNow,"Dependency pending"));
        Assert.Equal("Retry",result.Status); Assert.Equal(SyncErrorCodes.ServerError,result.ErrorCode); Assert.Empty(test.Db.InboundOperations); Assert.DoesNotContain(test.Db.CashMovements,x=>x.GlobalId==movementId);
    }

    [Fact]
    public async Task Historical_movement_before_close_is_accepted_but_after_close_is_rejected()
    {
        await using var test=await TestDatabase.CreateAsync(); var tenant=await test.SeedTenantAsync("ClosedSession",role:"Manager");
        var openedAt=DateTimeOffset.UtcNow.AddHours(-2); var closedAt=DateTimeOffset.UtcNow.AddHours(-1); var session=await AddSessionAsync(test,tenant,openedAt,closedAt);
        var acceptedId=Guid.NewGuid(); var accepted=await PushAsync(test,tenant,Operation(Guid.NewGuid(),acceptedId,tenant,session.GlobalId,"ManualIn",100,openedAt.AddMinutes(30),"Movimiento pendiente"));
        Assert.Equal("Applied",accepted.Status); Assert.Contains(test.Db.CashMovements,x=>x.GlobalId==acceptedId);
        var rejectedId=Guid.NewGuid(); var rejected=await PushAsync(test,tenant,Operation(Guid.NewGuid(),rejectedId,tenant,session.GlobalId,"ManualIn",100,closedAt.AddMinutes(1),"Fuera de turno"));
        Assert.Equal("Rejected",rejected.Status); Assert.Equal(SyncErrorCodes.ValidationFailed,rejected.ErrorCode); Assert.DoesNotContain(test.Db.CashMovements,x=>x.GlobalId==rejectedId);
    }

    private static async Task<CashSession> AddSessionAsync(TestDatabase test,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,DateTimeOffset? openedAt=null,DateTimeOffset? closedAt=null)
    {
        var opened=openedAt??DateTimeOffset.UtcNow.AddMinutes(-10);
        var session=new CashSession{GlobalId=Guid.NewGuid(),BusinessId=tenant.Business.Id,BranchId=tenant.Branch.Id,DeviceId=tenant.Device.Id,UserId=tenant.User.Id,OpenedAt=opened,OpeningBalanceCents=1000,Status=closedAt is null?"Open":"Closed",ClosedAt=closedAt,CountedCashCents=closedAt is null?null:1000,ExpectedCashCents=closedAt is null?null:1000,DifferenceCents=closedAt is null?null:0,UpdatedAt=DateTimeOffset.UtcNow};
        test.Db.CashSessions.Add(session); await test.Db.SaveChangesAsync(TestContext.Current.CancellationToken); return session;
    }

    private static SyncOperationDto Operation(Guid operationId,Guid movementId,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,Guid cashSessionGlobalId,string type,long amountCents,DateTimeOffset date,string notes,object? authorization=null)
    {
        using var document=JsonDocument.Parse(JsonSerializer.Serialize(new{globalId=movementId,businessGlobalId=tenant.Business.GlobalId,branchGlobalId=tenant.Branch.GlobalId,deviceGlobalId=tenant.Device.GlobalId,userGlobalId=tenant.User.GlobalId,cashSessionGlobalId,date,type,amountCents,notes,authorization}));
        return new SyncOperationDto(operationId,"CashMovement",movementId,"Create",1,document.RootElement.Clone());
    }

    private static async Task<SyncOperationResult> PushAsync(TestDatabase test,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,SyncOperationDto operation)
    {
        var response=await new SyncService(test.Db).PushAsync(new SyncPushRequest([operation]),Context(tenant),TestContext.Current.CancellationToken); return Assert.Single(response.Results);
    }

    private static SyncTenantContext Context((Business Business,Branch Branch,Device Device,UserAccount User) tenant)=>new(tenant.Business.Id,tenant.Business.GlobalId,tenant.Branch.Id,tenant.Branch.GlobalId,tenant.Device.Id,tenant.Device.GlobalId,tenant.User.Id,tenant.User.GlobalId,tenant.User.Role,tenant.Device.Mode);
}
