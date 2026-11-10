using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Infrastructure;
using PosFlutter.Web.Controllers;
using PosFlutter.Web.Services;

namespace Pos.Infrastructure.Tests;

public sealed class PurchasesControllerRequestTests
{
    [Fact]
    public async Task Null_purchase_body_is_a_400_not_an_exception_or_405()
    {
        await using var database = await TestDatabase.CreateAsync();
        var (business, branch, device, user) = await database.SeedTenantAsync();
        var context = new DefaultHttpContext { Session = new DictionarySession() };
        WebTenantSession.Store(context.Session, new SyncTenantContext(
            business.Id, business.GlobalId, branch.Id, branch.GlobalId, device.Id, device.GlobalId,
            user.Id, user.GlobalId, user.Role, device.Mode));
        var controller = new PurchasesController(database.Db, new PurchaseReceivingService(database.Db))
        {
            ControllerContext = new ControllerContext { HttpContext = context }
        };

        var result = await controller.Create(null, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Empty(await database.Db.Purchases.ToListAsync());
    }

    private sealed class DictionarySession : ISession
    {
        private readonly Dictionary<string, byte[]> values = [];
        public bool IsAvailable => true;
        public string Id => "purchase-request-test";
        public IEnumerable<string> Keys => values.Keys;
        public void Clear() => values.Clear();
        public Task CommitAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task LoadAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public void Remove(string key) => values.Remove(key);
        public void Set(string key, byte[] value) => values[key] = value;
        public bool TryGetValue(string key, out byte[] value) => values.TryGetValue(key, out value!);
    }
}
