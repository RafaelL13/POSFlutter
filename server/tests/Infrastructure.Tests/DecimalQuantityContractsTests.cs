using System;
using System.Linq;
using Pos.Application;
using Xunit;

namespace Pos.Infrastructure.Tests;

public sealed class DecimalQuantityContractsTests
{
    [Fact]
    public void Legacy_integer_sale_rules_unchanged()
    {
        Assert.Equal(300L, SaleRules.CalculateLineTotal(3, 100));
        SaleRules.ValidateLine(1, 100);
        Assert.Throws<ArgumentException>(() => SaleRules.ValidateLine(0, 100));
    }

    [Theory]
    [InlineData("0.500", 19999L, 10000L)]
    [InlineData("1.250", 19999L, 24999L)]
    [InlineData("2.750", 100L, 275L)]
    [InlineData("1", 19999L, 19999L)]
    [InlineData("0.001", 500L, 1L)]
    [InlineData("0.001", 499L, 0L)]
    public void Fractional_pricing_uses_exact_integer_cents(string raw, long unitPrice, long expected)
    {
        Assert.Equal(expected, SaleRules.CalculateLineTotal(decimal.Parse(raw,
            System.Globalization.CultureInfo.InvariantCulture), unitPrice));
    }

    [Theory]
    [InlineData("0")]
    [InlineData("-1")]
    [InlineData("0.0000005")]
    [InlineData("100000.001")]
    public void Invalid_quantities_fail_closed(string raw)
    {
        var quantity = decimal.Parse(raw, System.Globalization.CultureInfo.InvariantCulture);
        Assert.Throws<ArgumentOutOfRangeException>(() => DecimalQuantity.Validate(quantity));
    }

    [Fact]
    public void Piece_products_reject_fractional_quantities()
    {
        Assert.Throws<ArgumentException>(() => DecimalQuantity.Validate(1.250m, false));
        Assert.Equal(1000L, DecimalQuantity.ToMilli(1m, false));
    }

    [Fact]
    public void Fifo_is_exact_with_multiple_lots_and_shortfall_fails()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var lots = new[] { new DecimalFifoLot(a, 500, 15000),
            new DecimalFifoLot(b, 2000, 15200) };
        var allocations = DecimalQuantity.AllocateFifo(lots, 1250);
        Assert.Equal(2, allocations.Count);
        Assert.Equal(500, allocations[0].QuantityMilli);
        Assert.Equal(750, allocations[1].QuantityMilli);
        Assert.Equal(1250, allocations.Sum(x => x.QuantityMilli));
        Assert.Equal(18900L, allocations.Sum(x => x.CostCents));
        Assert.Throws<InvalidOperationException>(() => DecimalQuantity.AllocateFifo(lots, 2600));
    }

    [Theory]
    [InlineData("0.000001", 1L)]
    [InlineData("0.500000", 500000L)]
    [InlineData("1.250000", 1250000L)]
    [InlineData("2.750001", 2750001L)]
    public void Six_decimal_contract_round_trips_without_loss(string raw, long expectedMicro)
    {
        var quantity = decimal.Parse(raw, System.Globalization.CultureInfo.InvariantCulture);
        Assert.Equal(expectedMicro, DecimalQuantity.ToMicro(quantity));
        Assert.Equal(quantity, DecimalQuantity.FromMicro(expectedMicro));
    }

    [Fact]
    public void Legacy_milli_adapter_rejects_values_that_would_be_truncated()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => DecimalQuantity.ToMilli(0.000001m));
        Assert.Equal(1250L, DecimalQuantity.ToMilli(1.250m));
    }

    [Fact]
    public void Micro_fifo_consumes_and_prices_exact_component_quantities()
    {
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var lots = new[]
        {
            new DecimalFifoLot(first, 500000, 1000),
            new DecimalFifoLot(second, 1000000, 1200)
        };

        var allocations = DecimalQuantity.AllocateFifoMicro(lots, 1250000);

        Assert.Equal(new[] { 500000L, 750000L }, allocations.Select(x => x.QuantityMilli));
        Assert.Equal(1400L, allocations.Sum(x => x.CostCents));
    }
}
