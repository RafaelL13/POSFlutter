using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Pos.Domain;
using Pos.Infrastructure;

namespace Pos.Infrastructure.Tests;

/// <summary>
/// SQL Server-backed database used only by remote-report integration tests.
///
/// Each instance receives its own randomly named database and deletes it
/// during disposal. Other infrastructure tests continue using SQLite.
/// </summary>
public sealed class SqlServerTestDatabase : IAsyncDisposable
{
    private readonly string _databaseName;
    private readonly string _connectionString;

    public PosDbContext Db { get; private set; } = null!;

    private SqlServerTestDatabase()
    {
        var serverConnection =
            Environment.GetEnvironmentVariable("POSFLUTTER_TEST_SQLSERVER")
            ?? @"Server=(localdb)\MSSQLLocalDB;Integrated Security=True;Encrypt=False;TrustServerCertificate=True";

        _databaseName = $"POSFlutter_ReportTests_{Guid.NewGuid():N}";

        var builder = new SqlConnectionStringBuilder(serverConnection)
        {
            InitialCatalog = _databaseName,
            Pooling = false
        };

        _connectionString = builder.ConnectionString;
    }

    public static async Task<SqlServerTestDatabase> CreateAsync()
    {
        var test = new SqlServerTestDatabase();

        var options = new DbContextOptionsBuilder<PosDbContext>()
            .UseSqlServer(test._connectionString)
            .Options;

        test.Db = new PosDbContext(options);

        // The database name is unique per test, so this never points at an
        // application or user database.
        await test.Db.Database.EnsureCreatedAsync();

        return test;
    }

    public async Task<(Business Business, Branch Branch, Device Device, UserAccount User)>
        SeedTenantAsync(
            string suffix = "A",
            string role = "Administrator",
            string mode = "PointOfSale")
    {
        var now = DateTimeOffset.UtcNow;
        var password = PasswordHashing.Create("StrongPass123!");

        var business = new Business
        {
            GlobalId = Guid.NewGuid(),
            Name = $"Business {suffix}",
            CreatedAt = now,
            UpdatedAt = now
        };

        Db.Businesses.Add(business);
        await Db.SaveChangesAsync();

        var branch = new Branch
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = business.Id,
            Name = "Main",
            CreatedAt = now,
            UpdatedAt = now
        };

        Db.Branches.Add(branch);
        await Db.SaveChangesAsync();

        var device = new Device
        {
            GlobalId = Guid.NewGuid(),
            BranchId = branch.Id,
            Name = $"Device {suffix}",
            Mode = mode,
            CreatedAt = now,
            LastSyncAt = now
        };

        var user = new UserAccount
        {
            GlobalId = Guid.NewGuid(),
            BusinessId = business.Id,
            Name = $"Admin {suffix}",
            Username = $"admin{suffix}",
            PasswordHash = password.Hash,
            PasswordSalt = password.Salt,
            Role = role,
            CreatedAt = now,
            UpdatedAt = now
        };

        Db.AddRange(device, user);
        await Db.SaveChangesAsync();

        return (business, branch, device, user);
    }

    public async ValueTask DisposeAsync()
    {
        if (Db is null)
        {
            return;
        }

        try
        {
            await Db.Database.EnsureDeletedAsync();
        }
        finally
        {
            await Db.DisposeAsync();
        }
    }
}
