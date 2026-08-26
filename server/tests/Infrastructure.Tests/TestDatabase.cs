using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

public sealed class TestDatabase : IAsyncDisposable
{
    private readonly SqliteConnection _connection=new("Data Source=:memory:");
    public PosDbContext Db {get;private set;}=null!;
    public static async Task<TestDatabase> CreateAsync()
    {
        var t=new TestDatabase();await t._connection.OpenAsync();var options=new DbContextOptionsBuilder<PosDbContext>().UseSqlite(t._connection).Options;t.Db=new PosDbContext(options);await t.Db.Database.EnsureCreatedAsync();return t;
    }
    public async Task<(Business Business,Branch Branch,Device Device,UserAccount User)> SeedTenantAsync(string suffix="A",string role="Administrator",string mode="PointOfSale")
    {
        var now=DateTimeOffset.UtcNow;var password=PasswordHashing.Create("StrongPass123!");
        var b=new Business{GlobalId=Guid.NewGuid(),Name=$"Business {suffix}",CreatedAt=now,UpdatedAt=now};Db.Businesses.Add(b);await Db.SaveChangesAsync();
        var br=new Branch{GlobalId=Guid.NewGuid(),BusinessId=b.Id,Name="Main",CreatedAt=now,UpdatedAt=now};Db.Branches.Add(br);await Db.SaveChangesAsync();
        var d=new Device{GlobalId=Guid.NewGuid(),BranchId=br.Id,Name=$"Device {suffix}",Mode=mode,CreatedAt=now,LastSyncAt=now};
        var u=new UserAccount{GlobalId=Guid.NewGuid(),BusinessId=b.Id,Name=$"Admin {suffix}",Username=$"admin{suffix}",PasswordHash=password.Hash,PasswordSalt=password.Salt,Role=role,CreatedAt=now,UpdatedAt=now};Db.AddRange(d,u);await Db.SaveChangesAsync();return(b,br,d,u);
    }
    public async ValueTask DisposeAsync(){await Db.DisposeAsync();await _connection.DisposeAsync();}
}
