namespace Pos.Infrastructure.Tests;

public sealed class CentralInventoryStockReadContractTests
{
    [Fact]
    public void Program_exposes_authenticated_read_only_stock_endpoint()
    {
        var source =
            File.ReadAllText(
                FindApiFile("Program.cs"));

        Assert.Contains(
            "\"/api/internal/inventory-central/stock\"",
            source);

        Assert.Contains(
            "CentralInventoryAuthentication.IsAuthorized",
            source);

        Assert.Contains(
            "lot.BusinessId == business.Id",
            source);

        Assert.Contains(
            "lot.BranchId == branch.Id",
            source);

        Assert.Contains(
            "lot.AvailableQuantity > 0",
            source);

        Assert.Contains(
            "productLots.Sum(",
            source);

        Assert.Contains(
            "readOnly = true",
            source);

        var start =
            source.IndexOf(
                "\"/api/internal/inventory-central/stock\"",
                StringComparison.Ordinal);

        var end =
            source.IndexOf(
                "\"/api/internal/inventory-central/transfers\"",
                start,
                StringComparison.Ordinal);

        Assert.True(start >= 0);
        Assert.True(end > start);

        var endpoint =
            source[start..end];

        Assert.DoesNotContain(
            "SaveChanges",
            endpoint,
            StringComparison.Ordinal);

        Assert.DoesNotContain(
            "Add(",
            endpoint,
            StringComparison.Ordinal);

        Assert.DoesNotContain(
            "Update(",
            endpoint,
            StringComparison.Ordinal);

        Assert.DoesNotContain(
            "Remove(",
            endpoint,
            StringComparison.Ordinal);
    }

    private static string FindApiFile(string fileName)
    {
        var directory =
            new DirectoryInfo(
                AppContext.BaseDirectory);

        while (directory is not null)
        {
            var candidate =
                Path.Combine(
                    directory.FullName,
                    "src",
                    "Api",
                    fileName);

            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory =
                directory.Parent;
        }

        throw new FileNotFoundException(
            fileName);
    }
}