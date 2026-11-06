using System.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using PosFlutter.Web.Services;

namespace PosFlutter.Web.Controllers;

// P02: Administrative editor is LAB-only for writes. Does not change the legacy
// AdminProductsController or the API checkout; uses the existing tenant session.
[Route("admin/combos")]
public sealed class AdminCombosController(PosDbContext db, IConfiguration config, ILogger<AdminCombosController> logger) : Controller
{
    private const string LabDatabase = "POSFlutter_MvcLab_PS25_IIS_20261023_174342";

    private bool MayWriteLab() =>
        config.GetValue<bool>("AdminCombos:AllowLabWrites") &&
        string.Equals(db.Database.GetDbConnection().Database, LabDatabase, StringComparison.OrdinalIgnoreCase) &&
        Request.IsHttps &&
        string.Equals(Request.Host.Host, "localhost", StringComparison.OrdinalIgnoreCase) &&
        Request.Host.Port == 18513;

    private async Task<Pos.Application.SyncTenantContext?> AdminContextAsync(CancellationToken ct)
    {
        var tenant = WebTenantSession.Read(HttpContext.Session);
        if (tenant is null || tenant.Role != "Administrator") return null;
        if (!await db.Users.AsNoTracking().AnyAsync(x => x.Id == tenant.UserId &&
              x.BusinessId == tenant.BusinessId && x.GlobalId == tenant.UserGlobalId &&
              x.Active && x.Role == "Administrator", ct)) return null;
        if (!await db.Businesses.AsNoTracking().AnyAsync(x => x.Id == tenant.BusinessId &&
              x.GlobalId == tenant.BusinessGlobalId && x.Active, ct)) return null;
        if (!await db.Branches.AsNoTracking().AnyAsync(x => x.Id == tenant.BranchId &&
              x.BusinessId == tenant.BusinessId && x.GlobalId == tenant.BranchGlobalId && x.Active, ct)) return null;
        if (!await db.Devices.AsNoTracking().AnyAsync(x => x.Id == tenant.DeviceId &&
              x.BranchId == tenant.BranchId && x.GlobalId == tenant.DeviceGlobalId &&
              x.Active && x.Mode == tenant.DeviceMode, ct)) return null;
        return tenant;
    }

    [HttpGet("")]
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        if (await AdminContextAsync(ct) is null) return StatusCode(403);
        ViewData["CanWriteLab"] = MayWriteLab();
        return View("Index");
    }

    [HttpGet("data")]
    public async Task<IActionResult> Data(CancellationToken ct)
    {
        var tenant = await AdminContextAsync(ct);
        if (tenant is null) return StatusCode(403);
        try
        {
            await using var connection = new SqlConnection(db.Database.GetDbConnection().ConnectionString);
            await connection.OpenAsync(ct);
            var products = new List<object>();
            await using (var command = new SqlCommand(@"
SELECT GlobalId, Code, Name, SalePriceCents, Active
FROM dbo.Products WHERE BusinessId = @business
ORDER BY Name, GlobalId;", connection))
            {
                command.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                await using var reader = await command.ExecuteReaderAsync(ct);
                while (await reader.ReadAsync(ct))
                    products.Add(new { globalId = reader.GetGuid(0), code = reader.GetString(1),
                        name = reader.GetString(2), salePriceCents = reader.GetInt64(3), active = reader.GetBoolean(4) });
            }

            var combos = new List<ComboData>();
            var byId = new Dictionary<long, ComboData>();
            await using (var command = new SqlCommand(@"
SELECT TOP (250) Id, GlobalId, Code, Name, ComboPriceCents, ServerVersion, Active
FROM dbo.AdminCombos WHERE BusinessId = @business ORDER BY Name, Id;", connection))
            {
                command.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                await using var reader = await command.ExecuteReaderAsync(ct);
                while (await reader.ReadAsync(ct))
                {
                    var row = new ComboData(reader.GetGuid(1), reader.GetString(2), reader.GetString(3),
                        reader.GetInt64(4), reader.GetInt64(5), reader.GetBoolean(6));
                    combos.Add(row);
                    byId.Add(reader.GetInt64(0), row);
                }
            }
            await using (var command = new SqlCommand(@"
SELECT i.ComboId, i.ProductGlobalId, i.Quantity, i.FixedUnitPriceCents
FROM dbo.AdminComboItems AS i
JOIN dbo.AdminCombos AS c ON c.Id = i.ComboId
WHERE c.BusinessId = @business ORDER BY i.ComboId, i.ProductGlobalId;", connection))
            {
                command.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                await using var reader = await command.ExecuteReaderAsync(ct);
                while (await reader.ReadAsync(ct))
                    if (byId.TryGetValue(reader.GetInt64(0), out var combo))
                        combo.Components.Add(new ComboComponentData(reader.GetGuid(1), reader.GetInt32(2),
                            reader.IsDBNull(3) ? null : reader.GetInt64(3)));
            }
            Response.Headers.CacheControl = "no-store";
            return Ok(new { products, combos, canWriteLab = MayWriteLab() });
        }
        catch (SqlException ex)
        {
            logger.LogError(ex, "P02 admin combo catalog database read failed");
            return StatusCode(503, new { code = "ADMIN_COMBOS_SQL_UNAVAILABLE" });
        }
    }

    [HttpPost("save")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Save([FromBody] SaveComboRequest? request, CancellationToken ct)
    {
        var tenant = await AdminContextAsync(ct);
        if (tenant is null) return StatusCode(403);
        if (!MayWriteLab()) return StatusCode(423, new { code = "LAB_COMBO_WRITES_DISABLED" });
        if (request is null || request.Components is not { Count: >= 1 and <= 20 } ||
            string.IsNullOrWhiteSpace(request.Code) || string.IsNullOrWhiteSpace(request.Name) ||
            request.Code.Trim().Length > 80 || request.Name.Trim().Length > 160 ||
            request.ComboPriceCents <= 0 || request.Components.Any(x =>
                x.ProductGlobalId == Guid.Empty || x.Quantity is < 1 or > 999 ||
                x.FixedUnitPriceCents is <= 0) ||
            request.Components.Select(x => x.ProductGlobalId).Distinct().Count() != request.Components.Count)
            return BadRequest(new { code = "INVALID_COMBO_INPUT" });

        bool creating = !request.GlobalId.HasValue || request.GlobalId.Value == Guid.Empty;
        // A supplied version is mandatory on edits; creates must not supply one.
        if (creating && request.ExpectedServerVersion.HasValue ||
            !creating && (!request.ExpectedServerVersion.HasValue || request.ExpectedServerVersion < 1))
            return BadRequest(new { code = "INVALID_COMBO_VERSION" });

        var comboId = creating ? Guid.NewGuid() : request.GlobalId!.Value;
        try
        {
            await using var connection = new SqlConnection(db.Database.GetDbConnection().ConnectionString);
            await connection.OpenAsync(ct);
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            long currentVersion = 0;
            long rowId = 0;
            await using (var lookup = new SqlCommand(@"
SELECT Id, ServerVersion FROM dbo.AdminCombos WITH (UPDLOCK, HOLDLOCK)
WHERE BusinessId = @business AND GlobalId = @global;", connection, transaction))
            {
                lookup.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                lookup.Parameters.Add("@global", SqlDbType.UniqueIdentifier).Value = comboId;
                await using var reader = await lookup.ExecuteReaderAsync(ct);
                if (await reader.ReadAsync(ct)) { rowId = reader.GetInt64(0); currentVersion = reader.GetInt64(1); }
            }
            if (creating && rowId != 0) return Conflict(new { code = "COMBO_ALREADY_EXISTS" });
            if (!creating && rowId == 0) return NotFound(new { code = "COMBO_NOT_FOUND" });
            if (!creating && currentVersion != request.ExpectedServerVersion)
                return Conflict(new { code = "COMBO_VERSION_CONFLICT", currentServerVersion = currentVersion });
            var code = request.Code.Trim();
            var name = request.Name.Trim();
            await using (var conflict = new SqlCommand(@"
SELECT COUNT_BIG(*) FROM dbo.AdminCombos WITH (UPDLOCK, HOLDLOCK)
WHERE BusinessId = @business AND Code = @code AND GlobalId <> @global;", connection, transaction))
            {
                conflict.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                conflict.Parameters.Add("@code", SqlDbType.NVarChar, 80).Value = code;
                conflict.Parameters.Add("@global", SqlDbType.UniqueIdentifier).Value = comboId;
                if ((long)(await conflict.ExecuteScalarAsync(ct) ?? 0L) > 0)
                    return Conflict(new { code = "COMBO_CODE_EXISTS" });
            }
            var prices = new Dictionary<Guid, long>();
            foreach (var item in request.Components)
            {
                await using var checkProduct = new SqlCommand(@"
SELECT SalePriceCents FROM dbo.Products WITH (UPDLOCK, HOLDLOCK)
WHERE BusinessId = @business AND GlobalId = @product AND Active = 1;", connection, transaction);
                checkProduct.Parameters.Add("@business", SqlDbType.BigInt).Value = tenant.BusinessId;
                checkProduct.Parameters.Add("@product", SqlDbType.UniqueIdentifier).Value = item.ProductGlobalId;
                var valueObject = await checkProduct.ExecuteScalarAsync(ct);
                if (valueObject is null) return BadRequest(new { code = "PRODUCT_NOT_ACTIVE_IN_BUSINESS" });
                prices.Add(item.ProductGlobalId, (long)valueObject);
            }
            try
            {
                // The SAME approved pricing-plan validator used by checkout.
                _ = WebComboPricingPlan.Create(comboId, creating ? 1 : currentVersion + 1, 1,
                    request.ComboPriceCents, request.Components.Select(x => new WebComboComponent(
                        x.ProductGlobalId, x.Quantity, prices[x.ProductGlobalId], x.FixedUnitPriceCents)).ToArray());
            }
            catch (Exception ex) when (ex is ArgumentException or OverflowException)
            {
                return BadRequest(new { code = "COMBO_PRICE_OR_QUANTITY_INVALID" });
            }
            if (creating)
            {
                await using var insert = new SqlCommand(@"
INSERT dbo.AdminCombos (BusinessId, GlobalId, Code, Name, ComboPriceCents, ServerVersion, Active, UpdatedAt)
OUTPUT INSERTED.Id
VALUES (@business, @global, @code, @name, @price, 1, @active, SYSDATETIMEOFFSET());", connection, transaction);
                SetMainParams(insert, tenant.BusinessId, comboId, code, name, request.ComboPriceCents, request.Active);
                rowId = (long)(await insert.ExecuteScalarAsync(ct) ?? throw new InvalidOperationException("Combo ID not returned."));
            }
            else
            {
                await using var update = new SqlCommand(@"
UPDATE dbo.AdminCombos SET Code=@code, Name=@name, ComboPriceCents=@price,
    Active=@active, ServerVersion=ServerVersion+1, UpdatedAt=SYSDATETIMEOFFSET()
WHERE BusinessId=@business AND GlobalId=@global AND ServerVersion=@expected;", connection, transaction);
                SetMainParams(update, tenant.BusinessId, comboId, code, name, request.ComboPriceCents, request.Active);
                update.Parameters.Add("@expected", SqlDbType.BigInt).Value = currentVersion;
                if (await update.ExecuteNonQueryAsync(ct) != 1)
                    return Conflict(new { code = "COMBO_VERSION_CONFLICT" });
                await using var delete = new SqlCommand("DELETE FROM dbo.AdminComboItems WHERE ComboId=@id;", connection, transaction);
                delete.Parameters.Add("@id", SqlDbType.BigInt).Value = rowId;
                await delete.ExecuteNonQueryAsync(ct);
            }
            foreach (var item in request.Components)
            {
                await using var insertItem = new SqlCommand(@"
INSERT dbo.AdminComboItems (ComboId, ProductGlobalId, Quantity, FixedUnitPriceCents)
VALUES (@combo, @product, @quantity, @fixed);", connection, transaction);
                insertItem.Parameters.Add("@combo", SqlDbType.BigInt).Value = rowId;
                insertItem.Parameters.Add("@product", SqlDbType.UniqueIdentifier).Value = item.ProductGlobalId;
                insertItem.Parameters.Add("@quantity", SqlDbType.Int).Value = item.Quantity;
                insertItem.Parameters.Add("@fixed", SqlDbType.BigInt).Value = (object?)item.FixedUnitPriceCents ?? DBNull.Value;
                await insertItem.ExecuteNonQueryAsync(ct);
            }
            await transaction.CommitAsync(ct);
            logger.LogInformation("P02 LAB admin combo {Action}; business={Business}; actor={Actor}; combo={Combo}",
                creating ? "create" : "update", tenant.BusinessGlobalId, tenant.UserGlobalId, comboId);
            return Ok(new { globalId = comboId, serverVersion = creating ? 1 : currentVersion + 1, saved = true });
        }
        catch (SqlException ex)
        {
            logger.LogError(ex, "P02 admin combo SQL failure (details withheld from client)");
            return StatusCode(503, new { code = "ADMIN_COMBO_SQL_FAILED" });
        }
    }

    private static void SetMainParams(SqlCommand cmd, long business, Guid id, string code,
        string name, long price, bool active)
    {
        cmd.Parameters.Add("@business", SqlDbType.BigInt).Value = business;
        cmd.Parameters.Add("@global", SqlDbType.UniqueIdentifier).Value = id;
        cmd.Parameters.Add("@code", SqlDbType.NVarChar, 80).Value = code;
        cmd.Parameters.Add("@name", SqlDbType.NVarChar, 160).Value = name;
        cmd.Parameters.Add("@price", SqlDbType.BigInt).Value = price;
        cmd.Parameters.Add("@active", SqlDbType.Bit).Value = active;
    }

    public sealed class ComboData(Guid id, string code, string name, long price, long version, bool active)
    {
        public Guid GlobalId { get; } = id;
        public string Code { get; } = code;
        public string Name { get; } = name;
        public long ComboPriceCents { get; } = price;
        public long ServerVersion { get; } = version;
        public bool Active { get; } = active;
        public List<ComboComponentData> Components { get; } = [];
    }
    public sealed record ComboComponentData(Guid ProductGlobalId, int Quantity, long? FixedUnitPriceCents);
}

public sealed record SaveComboRequest(Guid? GlobalId, long? ExpectedServerVersion, string Code, string Name,
    long ComboPriceCents, bool Active, List<SaveComboItem> Components);
public sealed record SaveComboItem(Guid ProductGlobalId, int Quantity, long? FixedUnitPriceCents);
