using Microsoft.EntityFrameworkCore;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class PosDbContext(DbContextOptions<PosDbContext> options) : DbContext(options)
{
    public DbSet<Business> Businesses => Set<Business>(); public DbSet<Branch> Branches => Set<Branch>(); public DbSet<Device> Devices => Set<Device>(); public DbSet<UserAccount> Users => Set<UserAccount>();
    public DbSet<Category> Categories => Set<Category>(); public DbSet<Supplier> Suppliers => Set<Supplier>(); public DbSet<Product> Products => Set<Product>(); public DbSet<Purchase> Purchases => Set<Purchase>(); public DbSet<PurchaseLine> PurchaseLines => Set<PurchaseLine>();
    public DbSet<InventoryLot> InventoryLots => Set<InventoryLot>(); public DbSet<InventoryMovement> InventoryMovements => Set<InventoryMovement>(); public DbSet<Sale> Sales => Set<Sale>(); public DbSet<SaleLine> SaleLines => Set<SaleLine>(); public DbSet<SaleLotAllocation> SaleLotAllocations => Set<SaleLotAllocation>();
    public DbSet<CashSession> CashSessions => Set<CashSession>(); public DbSet<Expense> Expenses => Set<Expense>(); public DbSet<InboundOperation> InboundOperations => Set<InboundOperation>(); public DbSet<SyncChange> SyncChanges => Set<SyncChange>(); public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>(); public DbSet<DeviceEnrollmentToken> DeviceEnrollmentTokens => Set<DeviceEnrollmentToken>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Business>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.Property(x=>x.Name).HasMaxLength(160); });
        b.Entity<Branch>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.Property(x=>x.Name).HasMaxLength(160); });
        b.Entity<Device>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.Property(x=>x.Name).HasMaxLength(120); e.Property(x=>x.Mode).HasMaxLength(32); e.ToTable(t=>t.HasCheckConstraint("CK_Device_Mode", "[Mode] IN ('PointOfSale','AdminReadOnly')")); });
        b.Entity<UserAccount>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.Username}).IsUnique(); e.Property(x=>x.Username).HasMaxLength(100); e.Property(x=>x.Role).HasMaxLength(32); });
        b.Entity<Category>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.Property(x=>x.Name).HasMaxLength(120); });
        b.Entity<Supplier>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.Property(x=>x.Name).HasMaxLength(180); });
        b.Entity<Product>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.Code}).IsUnique(); e.Property(x=>x.Code).HasMaxLength(80); e.Property(x=>x.Barcode).HasMaxLength(120); e.ToTable(t=>{ t.HasCheckConstraint("CK_Product_Price", "[SalePriceCents] >= 0"); t.HasCheckConstraint("CK_Product_MinStock", "[MinimumStock] >= 0"); }); });
        b.Entity<Purchase>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.HasMany(x=>x.Lines).WithOne().HasForeignKey(x=>x.PurchaseId).OnDelete(DeleteBehavior.Cascade); });
        b.Entity<PurchaseLine>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.HasOne(x=>x.Lot).WithOne().HasForeignKey<InventoryLot>(x=>x.PurchaseLineGlobalId).HasPrincipalKey<PurchaseLine>(x=>x.GlobalId).OnDelete(DeleteBehavior.Restrict); e.ToTable(t=>t.HasCheckConstraint("CK_PurchaseLine_Qty", "[Quantity] > 0")); });
        b.Entity<InventoryLot>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.BranchId,x.ProductGlobalId,x.EntryDate}); e.ToTable(t=>{ t.HasCheckConstraint("CK_Lot_Initial", "[InitialQuantity] > 0"); t.HasCheckConstraint("CK_Lot_Available", "[AvailableQuantity] >= 0 AND [AvailableQuantity] <= [InitialQuantity]"); t.HasCheckConstraint("CK_Lot_Cost", "[UnitCostCents] >= 0"); }); });
        b.Entity<InventoryMovement>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.BranchId,x.ProductGlobalId,x.MovementDate}); });
        b.Entity<Sale>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.IdempotencyKey}).IsUnique(); e.HasMany(x=>x.Lines).WithOne().HasForeignKey(x=>x.SaleId).OnDelete(DeleteBehavior.Cascade); });
        b.Entity<SaleLine>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.HasMany(x=>x.Lots).WithOne().HasForeignKey(x=>x.SaleLineId).OnDelete(DeleteBehavior.Cascade); e.ToTable(t=>t.HasCheckConstraint("CK_SaleLine_Qty", "[Quantity] > 0")); });
        b.Entity<SaleLotAllocation>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.GlobalId).IsUnique(); e.ToTable(t=>t.HasCheckConstraint("CK_SaleLot_Qty", "[Quantity] > 0")); });
        b.Entity<CashSession>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); });
        b.Entity<Expense>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.GlobalId}).IsUnique(); e.ToTable(t=>t.HasCheckConstraint("CK_Expense_Amount", "[AmountCents] > 0")); });
        b.Entity<InboundOperation>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>new{x.BusinessId,x.OperationGlobalId}).IsUnique(); });
        b.Entity<SyncChange>(e => { e.HasKey(x=>x.Id); e.Property(x=>x.Id).ValueGeneratedOnAdd(); e.HasIndex(x=>new{x.BusinessId,x.Id}); });
        b.Entity<RefreshToken>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.TokenHash).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.UserId,x.DeviceId}); });
        b.Entity<DeviceEnrollmentToken>(e => { e.HasKey(x=>x.Id); e.HasIndex(x=>x.TokenHash).IsUnique(); e.HasIndex(x=>new{x.BusinessId,x.ExpiresAt}); e.HasIndex(x=>x.GlobalId).IsUnique(); });
    }
}
