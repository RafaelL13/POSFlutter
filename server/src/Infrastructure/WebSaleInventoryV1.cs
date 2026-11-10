using System.Text.Json;
using Pos.Domain;

namespace Pos.Infrastructure;

// P049 CONTRACT ONLY: not published to SyncChanges, and not wired to checkout.
// Publishing before capability negotiation would break existing Android clients.
public static class WebSaleInventoryV1
{
    public const string EntityType = "WebSaleInventory";
    public const int Version = 1;

    public static string Serialize(Sale sale, Guid businessGlobalId, Guid branchGlobalId)
    {
        ArgumentNullException.ThrowIfNull(sale);
        if (sale.GlobalId == Guid.Empty || businessGlobalId == Guid.Empty || branchGlobalId == Guid.Empty)
            throw new ArgumentException("Missing event identity.");
        if (sale.Status != "Confirmed" || sale.Lines.Count == 0)
            throw new InvalidOperationException("Only confirmed sales with lines are supported.");
        if (sale.Lines.Any(x => x.ProductGlobalId == Guid.Empty || x.Quantity <= 0 || x.Lots.Count == 0 ||
            x.Lots.Any(l => l.InventoryLotGlobalId == Guid.Empty || l.Quantity <= 0) ||
            x.Lots.Sum(l => (long)l.Quantity) != x.Quantity))
            throw new InvalidOperationException("Incomplete FIFO lot allocations.");
        if (sale.Lines.GroupBy(x => x.ProductGlobalId).Any(x => x.Count() != 1))
            throw new InvalidOperationException("Duplicate products in sale.");
        if (sale.Lines.SelectMany(x => x.Lots).GroupBy(x => x.InventoryLotGlobalId).Any(x => x.Count() != 1))
            throw new InvalidOperationException("Duplicate lot allocation.");

        return JsonSerializer.Serialize(new
        {
            contractVersion = Version,
            globalId = sale.GlobalId,
            businessGlobalId,
            branchGlobalId,
            date = sale.SaleDateTime,
            lines = sale.Lines.Select(line => new
            {
                productGlobalId = line.ProductGlobalId,
                quantity = line.Quantity,
                lots = line.Lots.Select(lot => new
                {
                    lotGlobalId = lot.InventoryLotGlobalId,
                    quantity = lot.Quantity
                }).ToArray()
            }).ToArray()
        }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
    }
}
