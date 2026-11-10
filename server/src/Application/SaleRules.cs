namespace Pos.Application;
public static class SaleRules
{
    // Existing integer contracts stay unchanged for AV96/AV97 and all v1 sync clients.
    public static void ValidateLine(int quantity, long unitPriceCents)
    {
        if (quantity <= 0) throw new ArgumentException("Quantity must be positive.");
        if (unitPriceCents < 0) throw new ArgumentException("Price cannot be negative.");
    }

    public static long CalculateLineTotal(int quantity, long unitPriceCents) =>
        checked((long)quantity * unitPriceCents);

    // New overload is opt-in until SQL, SQLite and sync contracts migrate together.
    public static void ValidateLine(decimal quantity, long unitPriceCents,
        bool fractionalAllowed = true)
    {
        DecimalQuantity.Validate(quantity, fractionalAllowed);
        if (unitPriceCents < 0) throw new ArgumentException("Price cannot be negative.");
    }

    public static long CalculateLineTotal(decimal quantity, long unitPriceCents,
        bool fractionalAllowed = true) =>
        DecimalQuantity.PricedCents(quantity, unitPriceCents, fractionalAllowed);
}
