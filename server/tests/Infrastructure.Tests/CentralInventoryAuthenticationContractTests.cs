namespace Pos.Infrastructure.Tests;

public sealed class CentralInventoryAuthenticationContractTests
{
    [Fact]
    public void Program_exposes_internal_central_inventory_transfer_endpoint()
    {
        var source = File.ReadAllText(FindApiFile("Program.cs"));

        Assert.Contains(
            "\"/api/internal/inventory-central/transfers\"",
            source);

        Assert.Contains(
            "CentralInventoryAuthentication.IsAuthorized",
            source);

        Assert.Contains(
            "ICentralInventoryTransferService service",
            source);

        Assert.Contains(
            "service.ReceiveAsync(",
            source);
    }

    [Fact]
    public void Central_inventory_authentication_uses_dedicated_header_and_configuration()
    {
        var source = File.ReadAllText(
            FindApiFile("CentralInventoryAuthentication.cs"));

        Assert.Contains(
            "X-Central-Inventory-Key",
            source);

        Assert.Contains(
            "CentralInventory:ApiKey",
            source);

        Assert.Contains(
            "CryptographicOperations.FixedTimeEquals",
            source);

        Assert.DoesNotContain(
            "Authorization",
            source);

        Assert.DoesNotContain(
            "Bearer",
            source);
    }

    [Fact]
    public void Central_inventory_api_key_is_not_committed_in_appsettings()
    {
        var apiDirectory =
            Path.GetDirectoryName(FindApiFile("Program.cs"))!;

        foreach (var file in Directory.GetFiles(
                     apiDirectory,
                     "appsettings*.json"))
        {
            var source = File.ReadAllText(file);

            Assert.DoesNotContain(
                "\"ApiKey\"",
                source);
        }
    }

    private static string FindApiFile(string fileName)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "src",
                "Api",
                fileName);

            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException(
            $"Could not locate API file '{fileName}'.");
    }
}