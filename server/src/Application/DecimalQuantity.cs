using System;
using System.Collections.Generic;

namespace Pos.Application;

/// <summary>
/// Exact quantity arithmetic for versioned fractional-quantity contracts.
/// Values are represented as integer micro-units at the persistence boundary; this
/// deliberately avoids binary floating point in stock and FIFO calculations.
/// </summary>
public static class DecimalQuantity
{
    public const int Scale = 6;
    public const long UnitsPerWhole = 1_000_000L;
    public const long MilliUnitsPerWhole = 1_000L;
    public const decimal MaxQuantity = 100000m;

    public static decimal Validate(decimal quantity, bool fractionalAllowed = true)
    {
        if (quantity <= 0m || quantity > MaxQuantity ||
            decimal.Truncate(quantity * UnitsPerWhole) != quantity * UnitsPerWhole)
            throw new ArgumentOutOfRangeException(nameof(quantity),
                "Quantity must be positive, at most 100000, and have no more than six decimal places.");
        if (!fractionalAllowed && quantity != decimal.Truncate(quantity))
            throw new ArgumentException("Product requires whole units.", nameof(quantity));
        return quantity;
    }

    /// <summary>Converts a quantity to its exact six-decimal storage representation.</summary>
    public static long ToMicro(decimal quantity, bool fractionalAllowed = true) =>
        checked((long)(Validate(quantity, fractionalAllowed) * UnitsPerWhole));

    /// <summary>Restores an exact six-decimal storage representation.</summary>
    public static decimal FromMicro(long micro)
    {
        if (micro <= 0 || micro > MaxQuantity * UnitsPerWhole)
            throw new ArgumentOutOfRangeException(nameof(micro));
        return micro / (decimal)UnitsPerWhole;
    }

    /// <summary>
    /// Legacy milli-unit adapter. Existing three-decimal contracts remain exact and
    /// must not silently truncate a six-decimal value.
    /// </summary>
    public static long ToMilli(decimal quantity, bool fractionalAllowed = true)
    {
        var micro = ToMicro(quantity, fractionalAllowed);
        if (micro % (UnitsPerWhole / MilliUnitsPerWhole) != 0)
            throw new ArgumentOutOfRangeException(nameof(quantity),
                "Legacy milli-unit contracts cannot represent this quantity without truncation.");
        return micro / (UnitsPerWhole / MilliUnitsPerWhole);
    }

    public static decimal FromMilli(long milli)
    {
        if (milli <= 0 || milli > 100000000L)
            throw new ArgumentOutOfRangeException(nameof(milli));
        return milli / (decimal)MilliUnitsPerWhole;
    }

    /// <summary>Price for a whole commercial unit, rounded ONCE per sale line to integer cents.</summary>
    public static long PricedCents(decimal quantity, long unitPriceCents,
        bool fractionalAllowed = true)
    {
        Validate(quantity, fractionalAllowed);
        if (unitPriceCents < 0) throw new ArgumentOutOfRangeException(nameof(unitPriceCents));
        return checked((long)decimal.Round(
            checked(quantity * unitPriceCents), 0, MidpointRounding.AwayFromZero));
    }

    /// <summary>Consumes whole milli-units from FIFO lots in list order; no floating point.</summary>
    public static IReadOnlyList<DecimalFifoAllocation> AllocateFifo(
        IReadOnlyList<DecimalFifoLot> lots, long requestedMilli)
    {
        if (lots is null) throw new ArgumentNullException(nameof(lots));
        FromMilli(requestedMilli);
        var result = new List<DecimalFifoAllocation>();
        var remaining = requestedMilli;
        foreach (var lot in lots)
        {
            if (remaining == 0) break;
            if (lot.AvailableMilli < 0 || lot.UnitCostCents < 0)
                throw new ArgumentException("Invalid FIFO lot.", nameof(lots));
            if (lot.AvailableMilli == 0) continue;
            var taken = Math.Min(lot.AvailableMilli, remaining);
            var cost = PricedCents(FromMilli(taken), lot.UnitCostCents);
            result.Add(new DecimalFifoAllocation(lot.LotId, taken, cost));
            remaining -= taken;
        }
        if (remaining != 0) throw new InvalidOperationException("Insufficient FIFO stock.");
        return result;
    }

    /// <summary>Six-decimal FIFO allocation used by versioned combo components.</summary>
    public static IReadOnlyList<DecimalFifoAllocation> AllocateFifoMicro(
        IReadOnlyList<DecimalFifoLot> lots, long requestedMicro)
    {
        if (lots is null) throw new ArgumentNullException(nameof(lots));
        FromMicro(requestedMicro);
        var result = new List<DecimalFifoAllocation>();
        var remaining = requestedMicro;
        foreach (var lot in lots)
        {
            if (lot.AvailableMilli < 0 || lot.UnitCostCents < 0)
                throw new ArgumentException("Invalid FIFO lot.", nameof(lots));
            if (lot.AvailableMilli == 0) continue;
            var taken = Math.Min(lot.AvailableMilli, remaining);
            var cost = PricedCents(FromMicro(taken), lot.UnitCostCents);
            result.Add(new DecimalFifoAllocation(lot.LotId, taken, cost));
            remaining -= taken;
            if (remaining == 0) break;
        }
        if (remaining != 0) throw new InvalidOperationException("Insufficient FIFO stock.");
        return result;
    }
}

public sealed record DecimalFifoLot(Guid LotId, long AvailableMilli, long UnitCostCents);
public sealed record DecimalFifoAllocation(Guid LotId, long QuantityMilli, long CostCents);
