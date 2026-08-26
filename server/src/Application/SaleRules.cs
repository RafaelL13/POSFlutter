namespace Pos.Application;
public static class SaleRules
{
    public static void ValidateLine(int quantity,long unitPriceCents)
    {
        if(quantity<=0) throw new ArgumentException("Quantity must be positive.");
        if(unitPriceCents<0) throw new ArgumentException("Price cannot be negative.");
    }
    public static long CalculateLineTotal(int quantity,long unitPriceCents)=>checked((long)quantity*unitPriceCents);
}
