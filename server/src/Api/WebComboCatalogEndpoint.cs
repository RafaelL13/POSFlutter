using System.Data;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;

namespace Pos.Api;

// Read-only projection. Checkout continues to resolve prices and stock independently.
public static class WebComboCatalogEndpoint
{
    public static IEndpointRouteBuilder MapWebComboCatalog(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/combos/catalog", async (HttpContext http, PosDbContext db, CancellationToken ct) =>
        {
            var tenant = TenantClaims.Require(http.User);
            if (tenant.BusinessId <= 0 || tenant.BranchId <= 0)
                return Results.Forbid();
            // Confirm active business/branch against DB; do not trust claims alone.
            var authorized = await db.Businesses.AsNoTracking().AnyAsync(
                x => x.Id == tenant.BusinessId && x.Active, ct)
                && await db.Branches.AsNoTracking().AnyAsync(
                    x => x.Id == tenant.BranchId && x.BusinessId == tenant.BusinessId && x.Active, ct);
            if (!authorized) return Results.Forbid();
            var result = new List<object>();
            await using var connection = new SqlConnection(db.Database.GetDbConnection().ConnectionString);
            await connection.OpenAsync(ct);
            await using var cmd = new SqlCommand(@"
SELECT c.GlobalId, c.Code, c.Name, c.ComboPriceCents, c.ServerVersion,
       i.ProductGlobalId, i.Quantity, i.FixedUnitPriceCents
FROM dbo.AdminCombos AS c
INNER JOIN dbo.AdminComboItems AS i ON i.ComboId = c.Id
INNER JOIN dbo.Products AS p ON p.GlobalId = i.ProductGlobalId
    AND p.BusinessId = c.BusinessId AND p.Active = 1
WHERE c.BusinessId = @business AND c.Active = 1
  -- Fail closed: checkout requires every component, its owning product and valid quantity.
  AND c.ComboPriceCents > 0 AND c.ServerVersion >= 1
  AND (SELECT COUNT_BIG(*) FROM dbo.AdminComboItems AS componentCount
       WHERE componentCount.ComboId = c.Id) BETWEEN 1 AND 20
  AND NOT EXISTS (
      SELECT 1 FROM dbo.AdminComboItems AS invalidItem
      LEFT JOIN dbo.Products AS referencedProduct
        ON referencedProduct.GlobalId = invalidItem.ProductGlobalId
       AND referencedProduct.BusinessId = c.BusinessId
       AND referencedProduct.Active = 1
      WHERE invalidItem.ComboId = c.Id
        AND (referencedProduct.Id IS NULL OR invalidItem.Quantity NOT BETWEEN 1 AND 999)
  )
  AND NOT EXISTS (
      SELECT 1 FROM dbo.AdminComboItems AS duplicateItem
      WHERE duplicateItem.ComboId = c.Id
      GROUP BY duplicateItem.ProductGlobalId HAVING COUNT_BIG(*) > 1
  )
  AND c.ComboPriceCents <= (
      SELECT SUM(CONVERT(bigint, priceItem.Quantity) * priceProduct.SalePriceCents)
      FROM dbo.AdminComboItems AS priceItem
      JOIN dbo.Products AS priceProduct
        ON priceProduct.GlobalId = priceItem.ProductGlobalId
       AND priceProduct.BusinessId = c.BusinessId AND priceProduct.Active = 1
      WHERE priceItem.ComboId = c.Id
  )
  -- Keep the public catalog consistent with WebComboPricingPlan:
  -- all-null uses the approved proportional allocation; all-fixed must reconcile.
  AND (
      NOT EXISTS (SELECT 1 FROM dbo.AdminComboItems AS f
                  WHERE f.ComboId = c.Id AND f.FixedUnitPriceCents IS NOT NULL)
      OR (
          NOT EXISTS (SELECT 1 FROM dbo.AdminComboItems AS f
                      WHERE f.ComboId = c.Id AND (f.FixedUnitPriceCents IS NULL OR f.FixedUnitPriceCents <= 0))
          AND c.ComboPriceCents = (
              SELECT SUM(CONVERT(bigint, f.Quantity) * f.FixedUnitPriceCents)
              FROM dbo.AdminComboItems AS f WHERE f.ComboId = c.Id
          )
      )
  )
ORDER BY c.GlobalId, i.ProductGlobalId;", connection);
            cmd.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
            var groups = new Dictionary<Guid, (string Code, string Name, long Price, long Version, List<object> Items)>();
            await using (var reader = await cmd.ExecuteReaderAsync(ct))
            {
                while (await reader.ReadAsync(ct))
                {
                    var id = reader.GetGuid(0);
                    if (!groups.TryGetValue(id, out var group))
                    {
                        group = (reader.GetString(1), reader.GetString(2), reader.GetInt64(3),
                            reader.GetInt64(4), new List<object>());
                        groups[id] = group;
                    }
                    group.Items.Add(new { productGlobalId = reader.GetGuid(5), quantity = reader.GetInt32(6),
                        fixedUnitPriceCents = reader.IsDBNull(7) ? (long?)null : reader.GetInt64(7) });
                }
            }
            foreach (var entry in groups)
                result.Add(new { comboGlobalId = entry.Key, code = entry.Value.Code,
                    name = entry.Value.Name, priceCents = entry.Value.Price,
                    serverVersion = entry.Value.Version, components = entry.Value.Items });
            http.Response.Headers.CacheControl = "no-store";
            return Results.Ok(new { items = result });
        }).RequireAuthorization();
        return app;
    }
}
