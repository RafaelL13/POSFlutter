using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using Pos.Domain;
using Pos.Infrastructure;

var connection = Environment.GetEnvironmentVariable("ConnectionStrings__SqlServer")
    ?? throw new InvalidOperationException("ConnectionStrings__SqlServer is required.");
var password = Environment.GetEnvironmentVariable("POSFLUTTER_LAB_PASSWORD")
    ?? throw new InvalidOperationException("POSFLUTTER_LAB_PASSWORD is required.");
var builder = new SqlConnectionStringBuilder(connection);
if (string.IsNullOrWhiteSpace(builder.InitialCatalog) ||
    !(builder.InitialCatalog.StartsWith("POSFlutter_MvcLab_", StringComparison.Ordinal) ||
      builder.InitialCatalog.StartsWith("POSWEB_AV96_CHECKOUT_", StringComparison.Ordinal) ||
      builder.InitialCatalog.StartsWith("POSWEB_AV97_PAYMENTS_", StringComparison.Ordinal) ||
      builder.InitialCatalog.StartsWith("POSWEB_AV98_INVENTORY_", StringComparison.Ordinal)))
    throw new InvalidOperationException("Use an explicitly named POSFlutter_MvcLab_, POSWEB_AV96_CHECKOUT_, POSWEB_AV97_PAYMENTS_, or POSWEB_AV98_INVENTORY_ database only.");
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
                     select new { BusinessGlobalId = existingBusiness.GlobalId, BranchGlobalId = existingBranch.GlobalId, DeviceGlobalId = existingDevice.GlobalId, UserGlobalId = existingUser.GlobalId, existingUser.Username }).SingleAsync();
    // This utility is guarded to the disposable lab database above. Keeping the
    // laboratory account aligned with its process-only secret makes reruns repeatable.
    var labUser = await db.Users.SingleAsync(x => x.Username == lab.Username);
    var labHash = PasswordHashing.Create(password);
    labUser.PasswordHash = labHash.Hash;
    labUser.PasswordSalt = labHash.Salt;
    labUser.UpdatedAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();
    if (string.Equals(Environment.GetEnvironmentVariable("POSFLUTTER_LAB_REVOKE_DEVICE"), "1", StringComparison.Ordinal))
    {
        var revokedDevice = await db.Devices.SingleAsync(x => x.GlobalId == lab.DeviceGlobalId);
        revokedDevice.Active = false;
        await db.SaveChangesAsync();
    }
    // Security-only fixtures remain confined to POSFlutter_MvcLab_* databases.
    // They permit HTTP authorization tests without using production identities.
    var labBusinessId = await db.Businesses.Where(x => x.GlobalId == lab.BusinessGlobalId).Select(x => x.Id).SingleAsync();
    var seller = await db.Users.SingleOrDefaultAsync(x => x.BusinessId == labBusinessId && x.Username == "seller.lab");
    if (seller is null)
    {
        var sellerHash = PasswordHashing.Create(password);
        seller = new UserAccount { GlobalId = Guid.NewGuid(), BusinessId = labBusinessId, Name = "Vendedor laboratorio", Username = "seller.lab", PasswordHash = sellerHash.Hash, PasswordSalt = sellerHash.Salt, Role = "Seller", Active = true, CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
        db.Users.Add(seller); await db.SaveChangesAsync();
    }
    else
    {
        var sellerHash = PasswordHashing.Create(password);
        seller.PasswordHash = sellerHash.Hash; seller.PasswordSalt = sellerHash.Salt; seller.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
    }
    var foreignBusiness = await db.Businesses.SingleOrDefaultAsync(x => x.Name == "POSFlutter MVC Foreign Lab");
    if (foreignBusiness is null)
    {
        var nowSecurity = DateTimeOffset.UtcNow;
        foreignBusiness = new Business { GlobalId = Guid.NewGuid(), Name = "POSFlutter MVC Foreign Lab", Active = true, CreatedAt = nowSecurity, UpdatedAt = nowSecurity };
        db.Businesses.Add(foreignBusiness); await db.SaveChangesAsync();
        var foreignBranch = new Branch { GlobalId = Guid.NewGuid(), BusinessId = foreignBusiness.Id, Name = "Sucursal ajena", Active = true, CreatedAt = nowSecurity, UpdatedAt = nowSecurity };
        db.Branches.Add(foreignBranch); await db.SaveChangesAsync();
        var foreignDevice = new Device { GlobalId = Guid.NewGuid(), BranchId = foreignBranch.Id, Name = "Dispositivo ajeno", Mode = "PointOfSale", Active = true, CreatedAt = nowSecurity, LastSyncAt = nowSecurity };
        var foreignHash = PasswordHashing.Create(password);
        var foreignUser = new UserAccount { GlobalId = Guid.NewGuid(), BusinessId = foreignBusiness.Id, Name = "Operador ajeno", Username = "foreign.lab", PasswordHash = foreignHash.Hash, PasswordSalt = foreignHash.Salt, Role = "Administrator", Active = true, CreatedAt = nowSecurity, UpdatedAt = nowSecurity };
        var foreignProduct = new Product { GlobalId = Guid.NewGuid(), BusinessId = foreignBusiness.Id, Code = "FOREIGN-001", Name = "Producto ajeno", Presentation = "Pieza", SalePriceCents = 1250, MinimumStock = 1, Active = true, UpdatedAt = nowSecurity };
        db.AddRange(foreignDevice, foreignUser, foreignProduct);
        await db.SaveChangesAsync();
        db.InventoryLots.Add(new InventoryLot { GlobalId = Guid.NewGuid(), BusinessId = foreignBusiness.Id, BranchId = foreignBranch.Id, ProductGlobalId = foreignProduct.GlobalId, EntryDate = nowSecurity, InitialQuantity = 10, AvailableQuantity = 10, UnitCostCents = 700, Active = true, CreatedAt = nowSecurity });
        await db.SaveChangesAsync();
    }
    var foreignSecurity = await (from foreignB in db.Businesses
                                 join foreignBr in db.Branches on foreignB.Id equals foreignBr.BusinessId
                                 join foreignD in db.Devices on foreignBr.Id equals foreignD.BranchId
                                 join foreignU in db.Users on foreignB.Id equals foreignU.BusinessId
                                 join foreignP in db.Products on foreignB.Id equals foreignP.BusinessId
                                 where foreignB.Id == foreignBusiness.Id && foreignU.Username == "foreign.lab"
                                 select new { foreignB.GlobalId, BranchGlobalId = foreignBr.GlobalId, DeviceGlobalId = foreignD.GlobalId, UserGlobalId = foreignU.GlobalId, ProductGlobalId = foreignP.GlobalId }).SingleAsync();
    var foreignLabUser = await db.Users.SingleAsync(x => x.GlobalId == foreignSecurity.UserGlobalId);
    var foreignLabHash = PasswordHashing.Create(password);
    foreignLabUser.PasswordHash = foreignLabHash.Hash; foreignLabUser.PasswordSalt = foreignLabHash.Salt; foreignLabUser.UpdatedAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();
    var linkedCashPayments = await db.SalePayments.CountAsync(x => x.Method == "Cash" && x.CashSessionId != null);
    var supplierId = await db.Suppliers.Where(x => x.BusinessId == labBusinessId)
        .OrderBy(x => x.Name).Select(x => (Guid?)x.GlobalId).FirstOrDefaultAsync();
    // Purchases and security fixtures can legitimately add products to a reused LAB.
    // Return the canonical seeded product when present, otherwise a deterministic
    // fallback, rather than treating a healthy multi-product catalog as corruption.
    var productId = await db.Products.Where(x => x.BusinessId == labBusinessId)
        .OrderByDescending(x => x.Code == "LAB-001").ThenBy(x => x.Code)
        .Select(x => (Guid?)x.GlobalId).FirstOrDefaultAsync();
    var purchaseMovements = await db.InventoryMovements.CountAsync(x => x.Type == "Purchase");
    var purchaseChanges = await db.SyncChanges.CountAsync(x => x.EntityType == "Purchase");
    Console.WriteLine($"BUSINESS={lab.BusinessGlobalId};BRANCH={lab.BranchGlobalId};DEVICE={lab.DeviceGlobalId};USER_GLOBAL={lab.UserGlobalId};USER={lab.Username};SELLER={seller.GlobalId};SELLER_USER={seller.Username};SUPPLIER={supplierId};PRODUCT={productId};FOREIGN_BUSINESS={foreignSecurity.GlobalId};FOREIGN_BRANCH={foreignSecurity.BranchGlobalId};FOREIGN_DEVICE={foreignSecurity.DeviceGlobalId};FOREIGN_USER={foreignSecurity.UserGlobalId};FOREIGN_USERNAME=foreign.lab;FOREIGN_PRODUCT={foreignSecurity.ProductGlobalId};PURCHASES={await db.Purchases.CountAsync()};PURCHASE_LINES={await db.PurchaseLines.CountAsync()};LOTS={await db.InventoryLots.CountAsync()};PURCHASE_MOVEMENTS={purchaseMovements};PURCHASE_CHANGES={purchaseChanges};SALES={await db.Sales.CountAsync()};PAYMENTS={await db.SalePayments.CountAsync()};LINKED_CASH_PAYMENTS={linkedCashPayments};MOVEMENTS={await db.InventoryMovements.CountAsync()};AVAILABLE={await db.InventoryLots.SumAsync(x => x.AvailableQuantity)}");
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
var supplier = new Supplier { GlobalId = Guid.NewGuid(), BusinessId = business.Id, Name = "Proveedor laboratorio", Active = true, UpdatedAt = now };
var product = new Product { GlobalId = Guid.NewGuid(), BusinessId = business.Id, Code = "LAB-001", Name = "Producto de laboratorio", Presentation = "Pieza", SalePriceCents = 1250, MinimumStock = 2, Active = true, UpdatedAt = now };
db.AddRange(device, user, supplier, product); await db.SaveChangesAsync();
db.InventoryLots.Add(new InventoryLot { GlobalId = Guid.NewGuid(), BusinessId = business.Id, BranchId = branch.Id, ProductGlobalId = product.GlobalId, EntryDate = now, InitialQuantity = 10, AvailableQuantity = 10, UnitCostCents = 700, Active = true, CreatedAt = now });
await db.SaveChangesAsync();
Console.WriteLine($"BUSINESS={business.GlobalId};DEVICE={device.GlobalId};USER={user.Username};SUPPLIER={supplier.GlobalId};PRODUCT={product.GlobalId}");
