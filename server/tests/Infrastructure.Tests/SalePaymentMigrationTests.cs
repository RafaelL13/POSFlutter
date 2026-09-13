using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class SalePaymentMigrationTests
{
    [Fact]
    public async Task Legacy_cash_sale_is_backfilled_once_by_additive_migration()
    {
        var server = Environment.GetEnvironmentVariable("POSFLUTTER_TEST_SQLSERVER")
            ?? @"Server=(localdb)\MSSQLLocalDB;Integrated Security=True;Encrypt=False;TrustServerCertificate=True";
        var builder = new SqlConnectionStringBuilder(server)
        {
            InitialCatalog = $"POSFlutter_PaymentMigration_{Guid.NewGuid():N}",
            Pooling = false
        };
        var options = new DbContextOptionsBuilder<PosDbContext>()
            .UseSqlServer(builder.ConnectionString).Options;

        await using var db = new PosDbContext(options);
        try
        {
            var migrator = db.GetService<IMigrator>();
            await migrator.MigrateAsync("20260902041950_InitialProductionSchema",TestContext.Current.CancellationToken);
            var tenant = await SeedLegacyTenantAsync(db);
            var now = DateTimeOffset.UtcNow;
            var sale = new Sale
            {
                GlobalId = Guid.NewGuid(),IdempotencyKey = Guid.NewGuid(),BusinessId = tenant.Business.Id,
                BranchId = tenant.Branch.Id,DeviceId = tenant.Device.Id,UserId = tenant.User.Id,Folio = "LEGACY-1",
                SaleDateTime = now,SubtotalCents = 1250,TotalCents = 1250,FifoCostCents = 500,
                GrossProfitCents = 750,PaymentMethod = "Cash",Status = "Confirmed",CreatedAt = now
            };
            db.Sales.Add(sale);
            await db.SaveChangesAsync(TestContext.Current.CancellationToken);

            await migrator.MigrateAsync(cancellationToken:TestContext.Current.CancellationToken);
            var payment = Assert.Single(await db.SalePayments.AsNoTracking().ToListAsync(TestContext.Current.CancellationToken));
            Assert.Equal(sale.GlobalId,payment.GlobalId);
            Assert.Equal(sale.Id,payment.SaleId);
            Assert.Equal("Cash",payment.Method);
            Assert.Equal(1250,payment.AmountCents);

            await migrator.MigrateAsync(cancellationToken:TestContext.Current.CancellationToken);
            Assert.Equal(1,await db.SalePayments.CountAsync(TestContext.Current.CancellationToken));
        }
        finally
        {
            await db.Database.EnsureDeletedAsync(TestContext.Current.CancellationToken);
        }
    }

    private static async Task<(Business Business,Branch Branch,Device Device,UserAccount User)> SeedLegacyTenantAsync(PosDbContext db)
    {
        var now = DateTimeOffset.UtcNow;
        var business = new Business { GlobalId = Guid.NewGuid(),Name = "Legacy",CreatedAt = now,UpdatedAt = now };
        db.Businesses.Add(business); await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var branch = new Branch { GlobalId = Guid.NewGuid(),BusinessId = business.Id,Name = "Main",CreatedAt = now,UpdatedAt = now };
        db.Branches.Add(branch); await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var device = new Device { GlobalId = Guid.NewGuid(),BranchId = branch.Id,Name = "POS",Mode = "PointOfSale",CreatedAt = now };
        var user = new UserAccount { GlobalId = Guid.NewGuid(),BusinessId = business.Id,Name = "Admin",Username = $"legacy-{Guid.NewGuid():N}",PasswordHash = "h",PasswordSalt = "s",Role = "Administrator",CreatedAt = now,UpdatedAt = now };
        db.AddRange(device,user); await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return (business,branch,device,user);
    }
}
