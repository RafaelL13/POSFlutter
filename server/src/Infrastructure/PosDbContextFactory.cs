using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Pos.Infrastructure;

public sealed class PosDbContextFactory : IDesignTimeDbContextFactory<PosDbContext>
{
    private const string FallbackConnectionString =
        "Server=(localdb)\\MSSQLLocalDB;"
        + "Database=POSFlutterDesign;"
        + "Trusted_Connection=True;"
        + "TrustServerCertificate=True;"
        + "MultipleActiveResultSets=true";

    public PosDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("POSFLUTTER_EF_CONNECTION_STRING")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__SqlServer")
            ?? FallbackConnectionString;

        var options = new DbContextOptionsBuilder<PosDbContext>()
            .UseSqlServer(connectionString)
            .Options;

        return new PosDbContext(options);
    }
}
