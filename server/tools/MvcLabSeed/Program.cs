using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using Pos.Domain;
using Pos.Infrastructure;

var connection = Environment.GetEnvironmentVariable("ConnectionStrings__SqlServer")
    ?? throw new InvalidOperationException("ConnectionStrings__SqlServer is required.");
var password = Environment.GetEnvironmentVariable("POSFLUTTER_LAB_PASSWORD")
    ?? throw new InvalidOperationException("POSFLUTTER_LAB_PASSWORD is required.");
var builder = new SqlConnectionStringBuilder(connection);
if (string.IsNullOrWhiteSpace(builder.InitialCatalog) || !builder.InitialCatalog.StartsWith("POSFlutter_MvcLab_", StringComparison.Ordinal))
    throw new InvalidOperationException("Use an explicitly named POSFlutter_MvcLab_ database only.");
var database = builder.InitialCatalog;
builder.InitialCatalog = "master";
await using (var master = new SqlConnection(builder.ConnectionString))
{
    await master.OpenAsync();
    await using var command = master.CreateCommand();
    command.CommandText = "IF DB_ID(@database) IS NULL BEGIN DECLARE @sql nvarchar(max) = N'CREATE DATABASE ' + QUOTENAME(@database); EXEC(@sql); END";
    command.Parameters.AddWithValue("@database", database);
    await command.ExecuteNonQueryAsync();
}
var options = new DbContextOptionsBuilder<PosDbContext>().UseSqlServer(connection).Options;
await using var db = new PosDbContext(options);
await db.Database.MigrateAsync();
if (await db.Businesses.AnyAsync())
{
    var lab = await (from existingBusiness in db.Businesses
                     join existingBranch in db.Branches on existingBusiness.Id equals existingBranch.BusinessId
                     join existingDevice in db.Devices on existingBranch.Id equals existingDevice.BranchId
                     join existingUser in db.Users on existingBusiness.Id equals existingUser.BusinessId
                     where existingBusiness.Name == "POSFlutter MVC Lab" && existingUser.Username == "web.lab"
                     select new { existingBusiness.GlobalId, DeviceGlobalId = existingDevice.GlobalId, existingUser.Username }).SingleAsync();
    // This utility is guarded to the disposable lab database above. Keeping the
    // laboratory account aligned with its process-only secret makes reruns repeatable.
    var labUser = await db.Users.SingleAsync(x => x.Username == lab.Username);
    var labHash = PasswordHashing.Create(password);
    labUser.PasswordHash = labHash.Hash;
    labUser.PasswordSalt = labHash.Salt;
    labUser.UpdatedAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();
    var linkedCashPayments = await db.SalePayments.CountAsync(x => x.Method == "Cash" && x.CashSessionId != null);
    Console.WriteLine($"BUSINESS={lab.GlobalId};DEVICE={lab.DeviceGlobalId};USER={lab.Username};SALES={await db.Sales.CountAsync()};PAYMENTS={await db.SalePayments.CountAsync()};LINKED_CASH_PAYMENTS={linkedCashPayments};MOVEMENTS={await db.InventoryMovements.CountAsync()};AVAILABLE={await db.InventoryLots.SumAsync(x => x.AvailableQuantity)}");
    return;
}
var now = DateTimeOffset.UtcNow;
var business = new Business { GlobalId = Guid.NewGuid(), Name = "POSFlutter MVC Lab", Active = true, CreatedAt = now, UpdatedAt = now };
db.Businesses.Add(business); await db.SaveChangesAsync();
var branch = new Branch { GlobalId = Guid.NewGuid(), BusinessId = business.Id, Name = "Laboratorio", Active = true, CreatedAt = now, UpdatedAt = now };
db.Branches.Add(branch); await db.SaveChangesAsync();
var device = new Device { GlobalId = Guid.NewGuid(), BranchId = branch.Id, Name = "Web Lab", Mode = "PointOfSale", Active = true, CreatedAt = now, LastSyncAt = now };
var hash = PasswordHashing.Create(password);
var user = new UserAccount { GlobalId = Guid.NewGuid(), BusinessId = business.Id, Name = "Operador laboratorio", Username = "web.lab", PasswordHash = hash.Hash, PasswordSalt = hash.Salt, Role = "Administrator", Active = true, CreatedAt = now, UpdatedAt = now };
var product = new Product { GlobalId = Guid.NewGuid(), BusinessId = business.Id, Code = "LAB-001", Name = "Producto de laboratorio", Presentation = "Pieza", SalePriceCents = 1250, MinimumStock = 2, Active = true, UpdatedAt = now };
db.AddRange(device, user, product); await db.SaveChangesAsync();
db.InventoryLots.Add(new InventoryLot { GlobalId = Guid.NewGuid(), BusinessId = business.Id, BranchId = branch.Id, ProductGlobalId = product.GlobalId, EntryDate = now, InitialQuantity = 10, AvailableQuantity = 10, UnitCostCents = 700, Active = true, CreatedAt = now });
await db.SaveChangesAsync();
Console.WriteLine($"BUSINESS={business.GlobalId};DEVICE={device.GlobalId};USER={user.Username};PRODUCT={product.GlobalId}");
