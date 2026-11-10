using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Pos.Application;

namespace Pos.Infrastructure;

// Combo tracing must commit in the same SQL transaction as checkout.
// Production is fail-closed unless an exact SQL target is approved explicitly.
internal static class WebComboCheckoutSwitch
{
    public static bool IsEnabledFor(System.Data.Common.DbConnection connection)
    {
        var database = connection.Database;
        if (string.IsNullOrWhiteSpace(database)) return false;
        // Preserve the previously approved LAB behavior, but never allow this flag
        // to enable a non-LAB database.
        if ((database.Contains("LAB", StringComparison.OrdinalIgnoreCase) ||
             database.Contains("TEST", StringComparison.OrdinalIgnoreCase)) &&
            StringComparer.Ordinal.Equals(
                Environment.GetEnvironmentVariable("POSWEB_COMBOS_LAB_ENABLE"), "1"))
            return true;

        if (!StringComparer.Ordinal.Equals(
                Environment.GetEnvironmentVariable("POSWEB_COMBOS_COMMERCIAL_ENABLE"), "1"))
            return false;
        var allowedDatabase = Environment.GetEnvironmentVariable("POSWEB_COMBOS_COMMERCIAL_DATABASE");
        var allowedServer = Environment.GetEnvironmentVariable("POSWEB_COMBOS_COMMERCIAL_SERVER");
        if (string.IsNullOrWhiteSpace(allowedDatabase) || string.IsNullOrWhiteSpace(allowedServer))
            return false;
        // Both values must match the active SQL connection exactly (case-insensitive).
        // Set these only after schema verification and authenticated HTTP UAT.
        return StringComparer.OrdinalIgnoreCase.Equals(database, allowedDatabase) &&
               StringComparer.OrdinalIgnoreCase.Equals(connection.DataSource, allowedServer);
    }
}

public static class WebComboSaleTrace
{
    private sealed record StoredIntent(
        WebCheckoutLine[] Products,
        WebCheckoutComboLine[] Combos);

    private static WebCheckoutLine[] CanonicalProducts(IReadOnlyList<WebCheckoutLine> lines) =>
        lines.OrderBy(x => x.ProductGlobalId).ToArray();

    private static WebCheckoutComboLine[] CanonicalCombos(IReadOnlyList<WebCheckoutComboLine>? combos) =>
        (combos ?? Array.Empty<WebCheckoutComboLine>()).OrderBy(x => x.ComboGlobalId).ToArray();

    private static string SerializeIntent(IReadOnlyList<WebCheckoutLine> lines,
        IReadOnlyList<WebCheckoutComboLine>? combos) =>
        JsonSerializer.Serialize(new StoredIntent(CanonicalProducts(lines), CanonicalCombos(combos)));

    public static async Task<bool> MatchesAsync(PosDbContext db, IDbContextTransaction tx,
        long businessId, Guid saleGlobalId, IReadOnlyList<WebCheckoutLine> products,
        IReadOnlyList<WebCheckoutComboLine>? combos, CancellationToken ct)
    {
        // Until LAB integration is certified preserve EXACTLY the previous product-only
        // replay behavior. No new table read is performed for existing checkouts.
        if (!WebComboCheckoutSwitch.IsEnabledFor(db.Database.GetDbConnection()))
            return combos is not { Count: > 0 };

        var connection = (SqlConnection)db.Database.GetDbConnection();
        var transaction = (SqlTransaction)tx.GetDbTransaction();
        await using var cmd = new SqlCommand(@"SELECT TOP (1) RequestIntentJson
FROM dbo.WebSaleComboSnapshots WITH (HOLDLOCK)
WHERE BusinessId=@business AND SaleGlobalId=@sale ORDER BY Ordinal", connection, transaction);
        cmd.Parameters.Add("@business", SqlDbType.BigInt).Value = businessId;
        cmd.Parameters.Add("@sale", SqlDbType.UniqueIdentifier).Value = saleGlobalId;
        var original = await cmd.ExecuteScalarAsync(ct) as string;
        return original is null
            ? combos is not { Count: > 0 }
            : StringComparer.Ordinal.Equals(original, SerializeIntent(products, combos));
    }

    public static async Task<bool> HasTraceAsync(PosDbContext db, IDbContextTransaction tx,
        long businessId, Guid saleGlobalId, CancellationToken ct)
    {
        var connection = (SqlConnection)db.Database.GetDbConnection();
        var transaction = (SqlTransaction)tx.GetDbTransaction();
        await using var cmd = new SqlCommand(@"SELECT TOP (1) 1 FROM dbo.WebSaleComboSnapshots WITH (HOLDLOCK)
WHERE BusinessId=@business AND SaleGlobalId=@sale", connection, transaction);
        cmd.Parameters.Add("@business", SqlDbType.BigInt).Value = businessId;
        cmd.Parameters.Add("@sale", SqlDbType.UniqueIdentifier).Value = saleGlobalId;
        return await cmd.ExecuteScalarAsync(ct) is not null;
    }

    public static async Task InsertAsync(PosDbContext db, IDbContextTransaction tx,
        long businessId, Guid saleGlobalId, IReadOnlyList<WebCheckoutLine> products,
        IReadOnlyList<WebComboPlan> plans, CancellationToken ct)
    {
        var connection = (SqlConnection)db.Database.GetDbConnection();
        var transaction = (SqlTransaction)tx.GetDbTransaction();
        var intent = SerializeIntent(products, plans.Select(x => new WebCheckoutComboLine(
            x.ComboGlobalId, x.ComboVersion, x.ComboQuantity)).ToArray());
        int ordinal = 0;
        foreach (var plan in plans.OrderBy(x => x.ComboGlobalId))
        {
            await using var cmd = new SqlCommand(@"INSERT dbo.WebSaleComboSnapshots
(BusinessId, SaleGlobalId, Ordinal, ComboGlobalId, ComboVersion, ComboQuantity,
ChargedCents, ComponentsJson, RequestIntentJson)
VALUES (@business,@sale,@ordinal,@combo,@version,@quantity,@total,@components,@intent)", connection, transaction);
            cmd.Parameters.Add("@business", SqlDbType.BigInt).Value = businessId;
            cmd.Parameters.Add("@sale", SqlDbType.UniqueIdentifier).Value = saleGlobalId;
            cmd.Parameters.Add("@ordinal", SqlDbType.Int).Value = ordinal++;
            cmd.Parameters.Add("@combo", SqlDbType.UniqueIdentifier).Value = plan.ComboGlobalId;
            cmd.Parameters.Add("@version", SqlDbType.BigInt).Value = plan.ComboVersion;
            cmd.Parameters.Add("@quantity", SqlDbType.Int).Value = plan.ComboQuantity;
            cmd.Parameters.Add("@total", SqlDbType.BigInt).Value = plan.ChargedCents;
            cmd.Parameters.Add("@components", SqlDbType.NVarChar, -1).Value = JsonSerializer.Serialize(plan.Lines);
            cmd.Parameters.Add("@intent", SqlDbType.NVarChar, -1).Value = intent;
            await cmd.ExecuteNonQueryAsync(ct);
        }
    }
}
