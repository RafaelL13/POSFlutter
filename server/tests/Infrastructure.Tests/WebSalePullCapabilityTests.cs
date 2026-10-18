using Pos.Infrastructure;
using Xunit;

namespace Pos.Infrastructure.Tests;

public sealed class WebSalePullCapabilityTests
{
    [Theory]
    [InlineData(null, false)]
    [InlineData("", false)]
    [InlineData("WebSaleInventory", false)]
    [InlineData("websaleinventoryv1", false)]
    [InlineData("WebSaleInventoryV1,SaleV2", false)]
    [InlineData("WebSaleInventoryV1", true)]
    public void Capability_opt_in_is_exact(string? value, bool expected)
    {
        Assert.Equal(expected, WebSaleSyncCapability.IsSupported(value));
    }
}
