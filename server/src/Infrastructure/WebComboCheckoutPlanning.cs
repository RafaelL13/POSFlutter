using System.Data;
using System.Numerics;
using Microsoft.Data.SqlClient;
using Pos.Application;

namespace Pos.Infrastructure;

// Pure, immutable plan. Resolving it never writes SQL or mutates checkout state.
// Optional explicit per-unit combo price. NULL preserves the approved proportional allocation.
public sealed record WebComboComponent(Guid ProductGlobalId, int QuantityPerCombo, long UnitRegularCents,
    long? FixedUnitPriceCents = null);
public sealed record WebComboPlannedLine(Guid ProductGlobalId, int Quantity, long RegularCents, long ChargedCents);
public sealed record WebComboPlan(Guid ComboGlobalId, long ComboVersion, int ComboQuantity,
    long RegularCents, long ChargedCents, IReadOnlyList<WebComboPlannedLine> Lines);

public static class WebComboPricingPlan
{
    public static WebComboPlan Create(Guid comboId, long version, int quantity, long priceCents,
        IReadOnlyList<WebComboComponent> components)
    {
        if (comboId == Guid.Empty || version < 1 || quantity is < 1 or > 1000 || priceCents <= 0 ||
            components is not { Count: >= 1 and <= 20 } ||
            components.Any(x => x.ProductGlobalId == Guid.Empty || x.QuantityPerCombo is < 1 or > 999 || x.UnitRegularCents < 0) ||
            components.Select(x => x.ProductGlobalId).Distinct().Count() != components.Count)
            throw new ArgumentException("Invalid combo definition or quantity.");
        var regular = components.Select(x => checked(checked(x.UnitRegularCents * x.QuantityPerCombo) * quantity)).ToArray();
        long regularTotal = 0;
        foreach (var value in regular) regularTotal = checked(regularTotal + value);
        long chargedTotal = checked(priceCents * quantity);
        if (regularTotal <= 0 || chargedTotal > regularTotal) throw new ArgumentException("Invalid promotional price.");
        // Commercial parity for explicitly-priced components (legacy PrecioFijo).
        // Existing combos with all NULL values retain their original proportional split.
        // A mixed definition is rejected to avoid undisclosed allocation changes.
        var usesFixedPrices = components.Any(x => x.FixedUnitPriceCents.HasValue);
        if (usesFixedPrices)
        {
            if (components.Any(x => x.FixedUnitPriceCents is null or <= 0))
                throw new ArgumentException("Every component must have a positive fixed price when fixed pricing is used.");
            var fixedCharges = components.Select(x =>
                checked(checked(x.FixedUnitPriceCents!.Value * x.QuantityPerCombo) * quantity)).ToArray();
            long fixedTotal = 0;
            foreach (var value in fixedCharges) fixedTotal = checked(fixedTotal + value);
            if (fixedTotal != chargedTotal)
                throw new ArgumentException("The sum of fixed component prices does not match the combo price.");
            return new(comboId, version, quantity, regularTotal, chargedTotal,
                Enumerable.Range(0, components.Count).Select(i =>
                    new WebComboPlannedLine(components[i].ProductGlobalId,
                        checked(components[i].QuantityPerCombo * quantity), regular[i], fixedCharges[i])).ToArray());
        }
        var charged = new long[components.Count];
        var leftovers = new BigInteger[components.Count];
        long assigned = 0;
        for (int i = 0; i < components.Count; i++)
        {
            var numerator = (BigInteger)regular[i] * chargedTotal;
            charged[i] = (long)(numerator / regularTotal);
            leftovers[i] = numerator % regularTotal;
            assigned = checked(assigned + charged[i]);
        }
        var residual = checked(chargedTotal - assigned);
        var order = Enumerable.Range(0, components.Count).OrderByDescending(i => leftovers[i])
            .ThenBy(i => components[i].ProductGlobalId).ToArray();
        for (long i = 0; i < residual; i++) charged[order[(int)i]]++;
        return new(comboId, version, quantity, regularTotal, chargedTotal,
            Enumerable.Range(0, components.Count).Select(i => new WebComboPlannedLine(components[i].ProductGlobalId,
                checked(components[i].QuantityPerCombo * quantity), regular[i], charged[i])).ToArray());
    }
}

// The caller must pass its EXISTING checkout transaction and connection. That ensures
// the eventual FIFO write uses the same snapshot/locks. No independent transaction here.
public static class WebComboCheckoutResolver
{
    public static async Task<WebComboPlan> ResolveAsync(SqlConnection connection, SqlTransaction transaction,
        long businessId, WebCheckoutComboLine selection, CancellationToken ct)
    {
        if (connection.State != ConnectionState.Open || transaction.Connection != connection ||
            businessId <= 0 || selection.ComboGlobalId == Guid.Empty || selection.ExpectedServerVersion < 1 ||
            selection.Quantity is < 1 or > 1000)
            throw new ArgumentException("Invalid combo checkout context.");
        await using var combo = new SqlCommand(@"
SELECT Id, ComboPriceCents, ServerVersion
FROM dbo.AdminCombos WITH (UPDLOCK, HOLDLOCK)
WHERE BusinessId=@business AND GlobalId=@combo AND Active=1;", connection, transaction);
        combo.Parameters.Add("@business", SqlDbType.BigInt).Value = businessId;
        combo.Parameters.Add("@combo", SqlDbType.UniqueIdentifier).Value = selection.ComboGlobalId;
        long id, price, version;
        await using (var reader = await combo.ExecuteReaderAsync(ct))
        {
            if (!await reader.ReadAsync(ct)) throw new InvalidOperationException("Combo missing or inactive.");
            id = reader.GetInt64(0); price = reader.GetInt64(1); version = reader.GetInt64(2);
        }
        if (version != selection.ExpectedServerVersion)
            throw new InvalidOperationException("Combo version changed; refresh catalog.");
        await using var items = new SqlCommand(@"
SELECT i.ProductGlobalId, i.Quantity, p.SalePriceCents, i.FixedUnitPriceCents
FROM dbo.AdminComboItems AS i WITH (HOLDLOCK)
LEFT JOIN dbo.Products AS p WITH (HOLDLOCK)
  ON p.GlobalId=i.ProductGlobalId AND p.BusinessId=@business AND p.Active=1
WHERE i.ComboId=@id ORDER BY i.ProductGlobalId;", connection, transaction);
        items.Parameters.Add("@business", SqlDbType.BigInt).Value = businessId;
        items.Parameters.Add("@id", SqlDbType.BigInt).Value = id;
        var components = new List<WebComboComponent>();
        await using (var reader = await items.ExecuteReaderAsync(ct))
        {
            while (await reader.ReadAsync(ct))
            {
                if (reader.IsDBNull(2)) throw new InvalidOperationException("Combo component missing or inactive.");
                components.Add(new(reader.GetGuid(0), reader.GetInt32(1), reader.GetInt64(2),
                    reader.IsDBNull(3) ? null : reader.GetInt64(3)));
            }
        }
        return WebComboPricingPlan.Create(selection.ComboGlobalId, version, selection.Quantity, price, components);
    }
}
