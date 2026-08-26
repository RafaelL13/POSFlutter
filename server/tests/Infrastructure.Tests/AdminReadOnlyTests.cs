using System.Text.Json;
using Pos.Application;
namespace Pos.Infrastructure.Tests;
public sealed class AdminReadOnlyTests
{
 [Fact] public async Task AdminReadOnly_cannot_push_but_can_pull(){await using var t=await TestDatabase.CreateAsync();var a=await t.SeedTenantAsync("R",mode:"AdminReadOnly");var s=new SyncService(t.Db);var ctx=new SyncTenantContext(a.Business.Id,a.Business.GlobalId,a.Branch.Id,a.Branch.GlobalId,a.Device.Id,a.Device.GlobalId,a.User.Id,a.User.GlobalId,a.User.Role,a.Device.Mode);using var doc=JsonDocument.Parse("{}");var push=await s.PushAsync(new SyncPushRequest([new SyncOperationDto(Guid.NewGuid(),"Sale",Guid.NewGuid(),"Create",1,doc.RootElement.Clone())]),ctx,CancellationToken.None);Assert.Equal("Rejected",push.Results.Single().Status);var pull=await s.PullAsync(0,100,ctx,CancellationToken.None);Assert.NotNull(pull);}
}
