using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class SyncService(PosDbContext db) : ISyncService
{
    private const string PointOfSaleMode = "PointOfSale";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly PosDbContext _db = db;

    public async Task<SyncPushResponse> PushAsync(
        SyncPushRequest request,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        if (request.Operations.Count is < 1 or > 100)
            throw new ArgumentException("Sync batch must contain between 1 and 100 operations.", nameof(request));

        await EnsureTenantActiveAsync(tenant, cancellationToken);
        if (!await IsPointOfSaleDeviceAsync(tenant, cancellationToken))
        {
            return new SyncPushResponse(
                request.Operations
                    .Select(operation => new SyncOperationResult(
                        operation.GlobalId,
                        "Rejected",
                        "This device is read-only and cannot push operational changes."))
                    .ToList(),
                DateTimeOffset.UtcNow);
        }

        var results = new List<SyncOperationResult>(request.Operations.Count);
        foreach (var operation in request.Operations)
        {
            try
            {
                EnsureOperationAuthorized(operation, tenant);
            }
            catch (UnauthorizedAccessException ex)
            {
                results.Add(new SyncOperationResult(operation.GlobalId, "Rejected", SafeSyncError(ex)));
                continue;
            }

            var alreadyProcessed = await _db.InboundOperations
                .AsNoTracking()
                .AnyAsync(
                    x => x.BusinessId == tenant.BusinessId && x.OperationGlobalId == operation.GlobalId,
                    cancellationToken);
            if (alreadyProcessed)
            {
                results.Add(new SyncOperationResult(operation.GlobalId, "AlreadyProcessed"));
                continue;
            }

            await using var transaction = await _db.Database.BeginTransactionAsync(cancellationToken);
            try
            {
                _db.InboundOperations.Add(new InboundOperation
                {
                    BusinessId = tenant.BusinessId,
                    OperationGlobalId = operation.GlobalId,
                    EntityType = operation.EntityType,
                    EntityGlobalId = operation.EntityGlobalId,
                    Operation = operation.Operation,
                    PayloadVersion = operation.PayloadVersion,
                    PayloadJson = operation.Payload.GetRawText(),
                    ReceivedAt = DateTimeOffset.UtcNow
                });

                await ApplyAsync(operation, tenant, cancellationToken);
                await _db.SaveChangesAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                results.Add(new SyncOperationResult(operation.GlobalId, "Applied"));
            }
            catch (CatalogConflictException ex)
            {
                await transaction.RollbackAsync(cancellationToken);
                _db.ChangeTracker.Clear();
                using var document = JsonDocument.Parse(ex.RemotePayloadJson);
                results.Add(new SyncOperationResult(
                    operation.GlobalId,
                    "Conflict",
                    "The catalog record changed on the server. Local data was not applied.",
                    ex.RemoteVersion,
                    document.RootElement.Clone()));
            }
            catch (InvalidOperationException ex)
            {
                await transaction.RollbackAsync(cancellationToken);
                _db.ChangeTracker.Clear();
                results.Add(new SyncOperationResult(operation.GlobalId, "Retry", SafeSyncError(ex)));
            }
            catch (DbUpdateException ex)
            {
                await transaction.RollbackAsync(cancellationToken);
                _db.ChangeTracker.Clear();
                var wonByAnotherRequest = await _db.InboundOperations.AsNoTracking().AnyAsync(
                    x => x.BusinessId == tenant.BusinessId && x.OperationGlobalId == operation.GlobalId,
                    cancellationToken);
                results.Add(wonByAnotherRequest
                    ? new SyncOperationResult(operation.GlobalId, "AlreadyProcessed")
                    : new SyncOperationResult(operation.GlobalId, "Rejected", SafeSyncError(ex)));
            }
            catch (Exception ex) when (ex is JsonException or ArgumentException or OverflowException)
            {
                await transaction.RollbackAsync(cancellationToken);
                _db.ChangeTracker.Clear();
                results.Add(new SyncOperationResult(operation.GlobalId, "Rejected", SafeSyncError(ex)));
            }
        }

        return new SyncPushResponse(results, DateTimeOffset.UtcNow);
    }

    public async Task<SyncPullResponse> PullAsync(
        long after,
        int take,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        if (after < 0) throw new ArgumentOutOfRangeException(nameof(after));
        take = Math.Clamp(take <= 0 ? 100 : take, 1, 200);
        await EnsureTenantActiveAsync(tenant, cancellationToken);

        var rows = await _db.SyncChanges.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.Id > after)
            .OrderBy(x => x.Id)
            .Take(take + 1)
            .ToListAsync(cancellationToken);

        var hasMore = rows.Count > take;
        if (hasMore) rows.RemoveAt(rows.Count - 1);
        var changes = new List<SyncPullChange>(rows.Count);
        foreach (var row in rows)
        {
            using var document = JsonDocument.Parse(row.PayloadJson);
            changes.Add(new SyncPullChange(
                row.Id,
                row.EntityType,
                row.EntityGlobalId,
                row.Operation,
                row.Version,
                row.CreatedAt,
                document.RootElement.Clone()));
        }

        var nextCursor = changes.Count == 0 ? after : changes[^1].Cursor;
        return new SyncPullResponse(nextCursor, hasMore, changes, DateTimeOffset.UtcNow);
    }

    private async Task ApplyAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        if (operation.PayloadVersion != 1)
            throw new ArgumentException($"Unsupported payload version {operation.PayloadVersion} for {operation.EntityType}.");
        if (operation.GlobalId == Guid.Empty || operation.EntityGlobalId == Guid.Empty)
            throw new ArgumentException("Sync operation IDs are required.");
        switch (operation.EntityType, operation.Operation)
        {
            case ("Business", "Create"):
            case ("Business", "Update"):
                await ApplyBusinessAsync(operation, tenant, cancellationToken);
                break;
            case ("Branch", "Create"):
            case ("Branch", "Update"):
                await ApplyBranchAsync(operation, tenant, cancellationToken);
                break;
            case ("Device", "Create"):
            case ("Device", "Update"):
                await ApplyDeviceAsync(operation, tenant, cancellationToken);
                break;
            case ("User", "Create"):
            case ("User", "Update"):
                await ApplyUserAsync(operation, tenant, cancellationToken);
                break;
            case ("Category", "Create"):
            case ("Category", "Update"):
                await ApplyCategoryAsync(operation, tenant, cancellationToken);
                break;
            case ("Supplier", "Create"):
            case ("Supplier", "Update"):
                await ApplySupplierAsync(operation, tenant, cancellationToken);
                break;
            case ("Product", "Create"):
            case ("Product", "Update"):
                await ApplyProductAsync(operation, tenant, cancellationToken);
                break;
            case ("Purchase", "Create"):
                await ApplyPurchaseAsync(operation, tenant, cancellationToken);
                break;
            case ("Expense", "Create"):
                await ApplyExpenseAsync(operation, tenant, cancellationToken);
                break;
            case ("InventoryAdjustment", "Create"):
                await ApplyInventoryAdjustmentAsync(operation, tenant, cancellationToken);
                break;
            case ("CashSession", "Create"):
            case ("CashSession", "Update"):
                await ApplyCashSessionAsync(operation, tenant, cancellationToken);
                break;
            case ("Sale", "Create"):
                await ApplySaleAsync(operation, tenant, cancellationToken);
                break;
            case ("Sale", "Cancel"):
                await ApplySaleCancellationAsync(operation, tenant, cancellationToken);
                break;
            default:
                throw new ArgumentException($"Unsupported sync operation: {operation.EntityType}/{operation.Operation}.");
        }
    }

    private async Task ApplyBusinessAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<BusinessSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        if (payload.GlobalId != tenant.BusinessGlobalId)
            throw new ArgumentException("Business payload does not belong to the authenticated tenant.");

        var entity = await _db.Businesses.SingleAsync(
            x => x.Id == tenant.BusinessId && x.GlobalId == tenant.BusinessGlobalId,
            cancellationToken);
        if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildBusinessPayload(entity));
            entity.Name = RequiredName(payload.Name, "Business");
            entity.Active = payload.Active;
            entity.UpdatedAt = DateTimeOffset.UtcNow;
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
        }

        AddChange(tenant.BusinessId, "Business", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildBusinessPayload(entity));
    }

    private async Task ApplyBranchAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<BranchSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        RequireBusiness(payload.BusinessGlobalId, tenant);
        var entity = await _db.Branches.SingleOrDefaultAsync(
            x => x.GlobalId == payload.GlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken);

        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"Branch {payload.GlobalId} has not been synchronized yet.");
            entity = new Branch
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                Name = RequiredName(payload.Name, "Branch"),
                Active = payload.Active,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow,
                ServerVersion = 1
            };
            _db.Branches.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildBranchPayload(entity, tenant.BusinessGlobalId));
            entity.Name = RequiredName(payload.Name, "Branch");
            entity.Active = payload.Active;
            entity.UpdatedAt = DateTimeOffset.UtcNow;
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
        }

        AddChange(tenant.BusinessId, "Branch", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildBranchPayload(entity, tenant.BusinessGlobalId));
    }

    private async Task ApplyDeviceAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<DeviceSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        var branch = await _db.Branches.AsNoTracking().SingleOrDefaultAsync(
            x => x.GlobalId == payload.BranchGlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken)
            ?? throw new InvalidOperationException($"Referenced branch {payload.BranchGlobalId} has not been synchronized yet.");

        var entity = await (
            from device in _db.Devices
            join tenantBranch in _db.Branches on device.BranchId equals tenantBranch.Id
            where device.GlobalId == payload.GlobalId && tenantBranch.BusinessId == tenant.BusinessId
            select device)
            .SingleOrDefaultAsync(cancellationToken);

        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"Device {payload.GlobalId} has not been synchronized yet.");
            entity = new Device
            {
                GlobalId = payload.GlobalId,
                BranchId = branch.Id,
                Name = RequiredName(payload.Name, "Device"),
                Mode = PointOfSaleMode,
                Active = payload.Active,
                CreatedAt = DateTimeOffset.UtcNow,
                LastSyncAt = DateTimeOffset.UtcNow,
                ServerVersion = 1
            };
            _db.Devices.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            var currentBranchGlobalId = await _db.Branches.AsNoTracking()
                .Where(x => x.Id == entity.BranchId && x.BusinessId == tenant.BusinessId)
                .Select(x => x.GlobalId)
                .SingleAsync(cancellationToken);
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildDevicePayload(entity, tenant.BusinessGlobalId, currentBranchGlobalId));
            entity.BranchId = branch.Id;
            entity.Name = RequiredName(payload.Name, "Device");
            entity.Active = payload.Active;
            entity.LastSyncAt = DateTimeOffset.UtcNow;
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
        }

        AddChange(tenant.BusinessId, "Device", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildDevicePayload(entity, tenant.BusinessGlobalId, branch.GlobalId));
    }

    private async Task ApplyUserAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<UserSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        RequireBusiness(payload.BusinessGlobalId, tenant);
        if (payload.Role is not ("Administrator" or "Seller" or "Supervisor" or "Manager"))
            throw new ArgumentException("Invalid user role.");
        if (string.IsNullOrWhiteSpace(payload.PasswordHash) || string.IsNullOrWhiteSpace(payload.PasswordSalt))
            throw new ArgumentException("User password material is required.");

        var entity = await _db.Users.SingleOrDefaultAsync(
            x => x.GlobalId == payload.GlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken);
        var now = DateTimeOffset.UtcNow;
        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"User {payload.GlobalId} has not been synchronized yet.");
            entity = new UserAccount
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                Name = RequiredName(payload.Name, "User"),
                Username = RequiredName(payload.Username, "Username"),
                PasswordHash = payload.PasswordHash,
                PasswordSalt = payload.PasswordSalt,
                Role = payload.Role,
                Active = payload.Active,
                CreatedAt = now,
                UpdatedAt = payload.UpdatedAt,
                ServerVersion = 1
            };
            _db.Users.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildUserPayload(entity, tenant.BusinessGlobalId));
            entity.Name = RequiredName(payload.Name, "User");
            entity.Username = RequiredName(payload.Username, "Username");
            entity.PasswordHash = payload.PasswordHash;
            entity.PasswordSalt = payload.PasswordSalt;
            entity.Role = payload.Role;
            entity.Active = payload.Active;
            entity.UpdatedAt = payload.UpdatedAt;
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
        }

        AddChange(tenant.BusinessId, "User", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildUserPayload(entity, tenant.BusinessGlobalId));
    }

    private async Task ApplyCategoryAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<CategorySyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        RequireBusiness(payload.BusinessGlobalId, tenant);
        var entity = await _db.Categories.SingleOrDefaultAsync(
            x => x.GlobalId == payload.GlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken);
        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"Category {payload.GlobalId} has not been synchronized yet.");
            entity = new Category
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                Name = RequiredName(payload.Name, "Category"),
                Description = Clean(payload.Description),
                Active = payload.Active,
                UpdatedAt = payload.UpdatedAt,
                ServerVersion = 1
            };
            _db.Categories.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildCategoryPayload(entity, tenant.BusinessGlobalId));
            entity.Name = RequiredName(payload.Name, "Category");
            entity.Description = Clean(payload.Description);
            entity.Active = payload.Active;
            entity.UpdatedAt = payload.UpdatedAt;
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
        }

        AddChange(tenant.BusinessId, "Category", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildCategoryPayload(entity, tenant.BusinessGlobalId));
    }

    private async Task ApplySupplierAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<SupplierSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        RequireBusiness(payload.BusinessGlobalId, tenant);
        var entity = await _db.Suppliers.SingleOrDefaultAsync(
            x => x.GlobalId == payload.GlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken);
        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"Supplier {payload.GlobalId} has not been synchronized yet.");
            entity = new Supplier
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                Name = RequiredName(payload.Name, "Supplier"),
                UpdatedAt = payload.UpdatedAt,
                ServerVersion = 1
            };
            _db.Suppliers.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildSupplierPayload(entity, tenant.BusinessGlobalId));
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
            AddChange(tenant.BusinessId, "Supplier", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildSupplierPayload(entity, tenant.BusinessGlobalId));
            return;
        }

        entity.Name = RequiredName(payload.Name, "Supplier");
        entity.ContactName = Clean(payload.ContactName);
        entity.Phone = Clean(payload.Phone);
        entity.Email = Clean(payload.Email);
        entity.Address = Clean(payload.Address);
        entity.Notes = Clean(payload.Notes);
        entity.Active = payload.Active;
        entity.UpdatedAt = payload.UpdatedAt;
        AddChange(tenant.BusinessId, "Supplier", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildSupplierPayload(entity, tenant.BusinessGlobalId));
    }

    private async Task ApplyProductAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<ProductSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        RequireBusiness(payload.BusinessGlobalId, tenant);
        if (payload.SalePriceCents < 0 || payload.MinimumStock < 0)
            throw new ArgumentException("Invalid product values.");
        if (payload.CategoryGlobalId is Guid categoryGlobalId &&
            !await _db.Categories.AsNoTracking().AnyAsync(
                x => x.GlobalId == categoryGlobalId && x.BusinessId == tenant.BusinessId,
                cancellationToken))
            throw new InvalidOperationException($"Referenced category {categoryGlobalId} has not been synchronized yet.");

        var entity = await _db.Products.SingleOrDefaultAsync(
            x => x.GlobalId == payload.GlobalId && x.BusinessId == tenant.BusinessId,
            cancellationToken);
        if (entity is null)
        {
            if (operation.Operation != "Create")
                throw new InvalidOperationException($"Product {payload.GlobalId} has not been synchronized yet.");
            entity = new Product
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                CategoryGlobalId = payload.CategoryGlobalId,
                Code = RequiredName(payload.Code, "Product code"),
                Barcode = Clean(payload.Barcode),
                Name = RequiredName(payload.Name, "Product"),
                Presentation = RequiredName(payload.Presentation, "Presentation"),
                SalePriceCents = payload.SalePriceCents,
                MinimumStock = payload.MinimumStock,
                Active = payload.Active,
                UpdatedAt = payload.UpdatedAt,
                ServerVersion = 1
            };
            _db.Products.Add(entity);
        }
        else if (operation.Operation == "Update")
        {
            EnsureExpectedVersion(operation, payload.BaseServerVersion, entity.ServerVersion, BuildProductPayload(entity, tenant.BusinessGlobalId));
            entity.ServerVersion++;
        }
        else
        {
            entity.ServerVersion = Math.Max(1, entity.ServerVersion);
            AddChange(tenant.BusinessId, "Product", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildProductPayload(entity, tenant.BusinessGlobalId));
            return;
        }

        entity.CategoryGlobalId = payload.CategoryGlobalId;
        entity.Code = RequiredName(payload.Code, "Product code");
        entity.Barcode = Clean(payload.Barcode);
        entity.Name = RequiredName(payload.Name, "Product");
        entity.Presentation = RequiredName(payload.Presentation, "Presentation");
        entity.SalePriceCents = payload.SalePriceCents;
        entity.MinimumStock = payload.MinimumStock;
        entity.Active = payload.Active;
        entity.UpdatedAt = payload.UpdatedAt;
        AddChange(tenant.BusinessId, "Product", entity.GlobalId, operation.Operation, entity.ServerVersion, BuildProductPayload(entity, tenant.BusinessGlobalId));
    }

    private async Task ApplyInventoryAdjustmentAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<InventoryAdjustmentSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        ValidateTransactionalContext(payload.BusinessGlobalId, payload.BranchGlobalId, payload.DeviceGlobalId, tenant);
        if (string.IsNullOrWhiteSpace(payload.Reason) || payload.QuantityDelta == 0 ||
            payload.Type is not ("ManualIn" or "ManualOut" or "Correction" or "Damage" or "Loss"))
            throw new ArgumentException("Invalid inventory adjustment.");
        if (await _db.InventoryMovements.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId,
            cancellationToken)) return;
        if (!await _db.Products.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.ProductGlobalId && x.Active,
            cancellationToken))
            throw new InvalidOperationException("Referenced product has not been synchronized yet.");

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        var previousStock = await _db.InventoryLots.AsNoTracking()
            .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId && x.ProductGlobalId == payload.ProductGlobalId && x.Active)
            .SumAsync(x => (int?)x.AvailableQuantity, cancellationToken) ?? 0;

        if (payload.QuantityDelta > 0)
        {
            if (payload.NewLotGlobalId is not Guid lotGlobalId || payload.UnitCostCents is null or < 0 || payload.Allocations.Count != 0)
                throw new ArgumentException("Inventory entry requires a new lot and unit cost.");
            if (await _db.InventoryLots.AsNoTracking().AnyAsync(x => x.BusinessId == tenant.BusinessId && x.GlobalId == lotGlobalId, cancellationToken))
                throw new ArgumentException("Inventory lot UUID is already in use.");
            _db.InventoryLots.Add(new InventoryLot
            {
                GlobalId = lotGlobalId,
                BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId,
                ProductGlobalId = payload.ProductGlobalId,
                PurchaseLineGlobalId = null,
                EntryDate = payload.Date,
                InitialQuantity = payload.QuantityDelta,
                AvailableQuantity = payload.QuantityDelta,
                UnitCostCents = payload.UnitCostCents.Value,
                Active = true,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }
        else
        {
            var expected = checked(-payload.QuantityDelta);
            if (payload.Allocations.Sum(x => x.Quantity) != expected || payload.Allocations.Any(x => x.Quantity <= 0 || x.UnitCostCents < 0))
                throw new ArgumentException("Inventory removal allocations do not match quantity.");
            foreach (var allocation in payload.Allocations)
            {
                var lot = await _db.InventoryLots.SingleOrDefaultAsync(
                    x => x.BusinessId == tenant.BusinessId && x.GlobalId == allocation.LotGlobalId,
                    cancellationToken) ?? throw new InvalidOperationException("Referenced inventory lot has not been synchronized yet.");
                if (lot.BranchId != tenant.BranchId || lot.ProductGlobalId != payload.ProductGlobalId || !lot.Active || lot.AvailableQuantity < allocation.Quantity)
                    throw new InvalidOperationException("Inventory lot cannot satisfy adjustment.");
                if (lot.UnitCostCents != allocation.UnitCostCents) throw new ArgumentException("Inventory lot cost mismatch.");
                lot.AvailableQuantity -= allocation.Quantity;
            }
        }
        var newStock = checked(previousStock + payload.QuantityDelta);
        if (newStock < 0) throw new InvalidOperationException("Server stock would become negative.");
        _db.InventoryMovements.Add(new InventoryMovement
        {
            GlobalId = payload.GlobalId,
            BusinessId = tenant.BusinessId,
            BranchId = tenant.BranchId,
            ProductGlobalId = payload.ProductGlobalId,
            MovementDate = payload.Date,
            Type = payload.Type,
            QuantityDelta = payload.QuantityDelta,
            PreviousStock = previousStock,
            NewStock = newStock,
            ReferenceGlobalId = payload.GlobalId,
            UserId = userId,
            DeviceId = tenant.DeviceId,
            Notes = payload.Reason.Trim()
        });
    }

    private async Task ApplyExpenseAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<ExpenseSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        ValidateTransactionalContext(payload.BusinessGlobalId, payload.BranchGlobalId, payload.DeviceGlobalId, tenant);
        if (payload.AmountCents <= 0 || string.IsNullOrWhiteSpace(payload.Concept))
            throw new ArgumentException("Invalid expense values.");
        if (payload.PaymentMethod is not ("Cash" or "Card" or "Transfer" or "Other"))
            throw new ArgumentException("Invalid expense payment method.");
        if (await _db.Expenses.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId,
            cancellationToken)) return;

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        _db.Expenses.Add(new Expense
        {
            GlobalId = payload.GlobalId,
            BusinessId = tenant.BusinessId,
            BranchId = tenant.BranchId,
            DeviceId = tenant.DeviceId,
            UserId = userId,
            ExpenseDate = payload.Date,
            Concept = payload.Concept.Trim(),
            Category = Clean(payload.Category),
            AmountCents = payload.AmountCents,
            PaymentMethod = payload.PaymentMethod,
            Notes = Clean(payload.Notes),
            CreatedAt = DateTimeOffset.UtcNow
        });
    }

    private async Task ApplyPurchaseAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<PurchaseSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        ValidateTransactionalContext(payload.BusinessGlobalId, payload.BranchGlobalId, payload.DeviceGlobalId, tenant);
        if (payload.Lines.Count == 0) throw new ArgumentException("Purchase must contain at least one line.");
        if (payload.TotalCents < 0) throw new ArgumentException("Invalid purchase total.");
        if (await _db.Purchases.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId,
            cancellationToken)) return;
        if (!await _db.Suppliers.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.SupplierGlobalId,
            cancellationToken))
            throw new InvalidOperationException($"Referenced supplier {payload.SupplierGlobalId} has not been synchronized yet.");

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var purchase = new Purchase
        {
            GlobalId = payload.GlobalId,
            BusinessId = tenant.BusinessId,
            BranchId = tenant.BranchId,
            DeviceId = tenant.DeviceId,
            UserId = userId,
            SupplierGlobalId = payload.SupplierGlobalId,
            PurchaseDate = payload.Date,
            Reference = Clean(payload.Reference),
            Notes = Clean(payload.Notes),
            TotalCents = payload.TotalCents,
            Status = "Confirmed",
            CreatedAt = now
        };

        var computedTotal = 0L;
        var stocks = new Dictionary<Guid, int>();
        foreach (var linePayload in payload.Lines)
        {
            if (linePayload.Quantity <= 0 || linePayload.UnitCostCents < 0)
                throw new ArgumentException("Invalid purchase line.");
            if (!await _db.Products.AsNoTracking().AnyAsync(
                x => x.GlobalId == linePayload.ProductGlobalId && x.BusinessId == tenant.BusinessId,
                cancellationToken))
                throw new InvalidOperationException($"Referenced product {linePayload.ProductGlobalId} has not been synchronized yet.");
            if (await _db.InventoryLots.AsNoTracking().AnyAsync(
                x => x.BusinessId == tenant.BusinessId && x.GlobalId == linePayload.LotGlobalId,
                cancellationToken))
                throw new ArgumentException("Inventory lot UUID is already in use for this tenant.");

            var subtotal = checked((long)linePayload.Quantity * linePayload.UnitCostCents);
            computedTotal = checked(computedTotal + subtotal);
            var line = new PurchaseLine
            {
                GlobalId = linePayload.DetailGlobalId,
                ProductGlobalId = linePayload.ProductGlobalId,
                Quantity = linePayload.Quantity,
                UnitCostCents = linePayload.UnitCostCents,
                SubtotalCents = subtotal,
                Lot = new InventoryLot
                {
                    GlobalId = linePayload.LotGlobalId,
                    BusinessId = tenant.BusinessId,
                    BranchId = tenant.BranchId,
                    ProductGlobalId = linePayload.ProductGlobalId,
                    PurchaseLineGlobalId = linePayload.DetailGlobalId,
                    EntryDate = payload.Date,
                    InitialQuantity = linePayload.Quantity,
                    AvailableQuantity = linePayload.Quantity,
                    UnitCostCents = linePayload.UnitCostCents,
                    Active = true,
                    CreatedAt = now
                }
            };
            purchase.Lines.Add(line);

            if (!stocks.TryGetValue(linePayload.ProductGlobalId, out var previousStock))
            {
                previousStock = await _db.InventoryLots.AsNoTracking()
                    .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId && x.ProductGlobalId == linePayload.ProductGlobalId && x.Active)
                    .SumAsync(x => (int?)x.AvailableQuantity, cancellationToken) ?? 0;
            }
            var newStock = checked(previousStock + linePayload.Quantity);
            stocks[linePayload.ProductGlobalId] = newStock;
            _db.InventoryMovements.Add(new InventoryMovement
            {
                GlobalId = Guid.NewGuid(),
                BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId,
                ProductGlobalId = linePayload.ProductGlobalId,
                MovementDate = payload.Date,
                Type = "Purchase",
                QuantityDelta = linePayload.Quantity,
                PreviousStock = previousStock,
                NewStock = newStock,
                ReferenceGlobalId = payload.GlobalId,
                UserId = userId,
                DeviceId = tenant.DeviceId,
                Notes = Clean(payload.Reference)
            });
        }
        if (computedTotal != payload.TotalCents)
            throw new ArgumentException("Purchase total does not equal the sum of lines.");
        _db.Purchases.Add(purchase);
    }

    private async Task ApplyCashSessionAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<CashSessionSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        ValidateTransactionalContext(payload.BusinessGlobalId, payload.BranchGlobalId, payload.DeviceGlobalId, tenant);
        if (payload.OpeningBalanceCents < 0 || payload.Status is not ("Open" or "Closed"))
            throw new ArgumentException("Invalid cash session values.");
        if (payload.Status == "Closed" &&
            (payload.ClosedAt is null || payload.CountedCashCents is null || payload.ExpectedCashCents is null || payload.DifferenceCents is null))
            throw new ArgumentException("Closed cash session is incomplete.");

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        var entity = await _db.CashSessions.SingleOrDefaultAsync(
            x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId,
            cancellationToken);
        if (entity is null)
        {
            _db.CashSessions.Add(new CashSession
            {
                GlobalId = payload.GlobalId,
                BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId,
                DeviceId = tenant.DeviceId,
                UserId = userId,
                OpenedAt = payload.OpenedAt,
                OpeningBalanceCents = payload.OpeningBalanceCents,
                Status = payload.Status,
                ClosedAt = payload.ClosedAt,
                CountedCashCents = payload.CountedCashCents,
                ExpectedCashCents = payload.ExpectedCashCents,
                DifferenceCents = payload.DifferenceCents,
                UpdatedAt = DateTimeOffset.UtcNow
            });
            return;
        }
        if (entity.BranchId != tenant.BranchId || entity.DeviceId != tenant.DeviceId)
            throw new ArgumentException("Cash session does not belong to the authenticated device.");
        entity.Status = payload.Status;
        entity.ClosedAt = payload.ClosedAt;
        entity.CountedCashCents = payload.CountedCashCents;
        entity.ExpectedCashCents = payload.ExpectedCashCents;
        entity.DifferenceCents = payload.DifferenceCents;
        entity.UpdatedAt = DateTimeOffset.UtcNow;
    }

    private async Task ApplySaleAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<SaleSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        ValidateTransactionalContext(payload.BusinessGlobalId, payload.BranchGlobalId, payload.DeviceGlobalId, tenant);

        var duplicate = await _db.Sales.AsNoTracking().AnyAsync(
            x => x.BusinessId == tenant.BusinessId &&
                 (x.GlobalId == payload.GlobalId || x.IdempotencyKey == payload.IdempotencyKey),
            cancellationToken);
        if (duplicate) return;

        if (payload.SubtotalCents < 0 || payload.DiscountCents < 0 || payload.DiscountCents > payload.SubtotalCents)
            throw new ArgumentException("Invalid sale totals.");
        if (payload.TotalCents != payload.SubtotalCents - payload.DiscountCents)
            throw new ArgumentException("Sale total does not match subtotal minus discount.");
        if (payload.FifoCostCents < 0 || payload.GrossProfitCents != payload.TotalCents - payload.FifoCostCents)
            throw new ArgumentException("Sale gross profit does not match FIFO cost.");
        if (payload.PaymentMethod is not ("Cash" or "Card" or "Transfer" or "Other"))
            throw new ArgumentException("Invalid payment method.");
        if (payload.Lines.Count == 0) throw new ArgumentException("Sale must contain at least one line.");

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        var sale = new Sale
        {
            GlobalId = payload.GlobalId,
            IdempotencyKey = payload.IdempotencyKey,
            BusinessId = tenant.BusinessId,
            BranchId = tenant.BranchId,
            DeviceId = tenant.DeviceId,
            UserId = userId,
            Folio = RequiredName(payload.Folio, "Folio"),
            SaleDateTime = payload.SaleDateTime,
            SubtotalCents = payload.SubtotalCents,
            DiscountCents = payload.DiscountCents,
            TotalCents = payload.TotalCents,
            FifoCostCents = payload.FifoCostCents,
            GrossProfitCents = payload.GrossProfitCents,
            PaymentMethod = payload.PaymentMethod,
            ReceivedCents = payload.ReceivedCents,
            ChangeCents = payload.ChangeCents,
            Status = "Confirmed",
            CreatedAt = DateTimeOffset.UtcNow
        };

        if (payload.Lines.Select(x => x.ProductGlobalId).Distinct().Count() != payload.Lines.Count)
            throw new ArgumentException("A product cannot appear twice in the same sale.");
        var consumedLotIds = new HashSet<Guid>();

        foreach (var linePayload in payload.Lines)
        {
            SaleRules.ValidateLine(linePayload.Quantity, linePayload.UnitPriceCents);
            if (!await _db.Products.AsNoTracking().AnyAsync(
                x => x.BusinessId == tenant.BusinessId && x.GlobalId == linePayload.ProductGlobalId,
                cancellationToken))
                throw new InvalidOperationException($"Referenced product {linePayload.ProductGlobalId} has not been synchronized yet.");
            if (linePayload.TotalCents != SaleRules.CalculateLineTotal(linePayload.Quantity, linePayload.UnitPriceCents))
                throw new ArgumentException("Sale line total is inconsistent.");
            var lotQuantity = linePayload.Lots.Sum(x => x.Quantity);
            var lotCost = linePayload.Lots.Sum(x => x.TotalCostCents);
            if (lotQuantity != linePayload.Quantity || lotCost != linePayload.FifoCostCents)
                throw new ArgumentException("FIFO lot allocations do not match sale line.");

            var previousStock = await _db.InventoryLots.AsNoTracking()
                .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == tenant.BranchId && x.ProductGlobalId == linePayload.ProductGlobalId && x.Active)
                .SumAsync(x => (int?)x.AvailableQuantity, cancellationToken) ?? 0;
            foreach (var lotPayload in linePayload.Lots)
            {
                if (!consumedLotIds.Add(lotPayload.LotGlobalId))
                    throw new ArgumentException("The same inventory lot cannot be consumed twice in one sale payload.");
                var inventoryLot = await _db.InventoryLots.SingleOrDefaultAsync(
                    x => x.BusinessId == tenant.BusinessId && x.GlobalId == lotPayload.LotGlobalId,
                    cancellationToken)
                    ?? throw new InvalidOperationException($"Inventory lot {lotPayload.LotGlobalId} has not been synchronized yet.");
                if (inventoryLot.BranchId != tenant.BranchId || inventoryLot.ProductGlobalId != linePayload.ProductGlobalId)
                    throw new ArgumentException("FIFO allocation references a lot from another branch or product.");
                if (!inventoryLot.Active || inventoryLot.AvailableQuantity < lotPayload.Quantity)
                    throw new InvalidOperationException($"Inventory lot {lotPayload.LotGlobalId} no longer has enough stock.");
                if (inventoryLot.UnitCostCents != lotPayload.UnitCostCents)
                    throw new ArgumentException("FIFO allocation cost does not match the synchronized lot cost.");
                inventoryLot.AvailableQuantity -= lotPayload.Quantity;
            }
            var newStock = checked(previousStock - linePayload.Quantity);
            if (newStock < 0) throw new InvalidOperationException("Server stock would become negative.");
            _db.InventoryMovements.Add(new InventoryMovement
            {
                GlobalId = Guid.NewGuid(),
                BusinessId = tenant.BusinessId,
                BranchId = tenant.BranchId,
                ProductGlobalId = linePayload.ProductGlobalId,
                MovementDate = payload.SaleDateTime,
                Type = "Sale",
                QuantityDelta = -linePayload.Quantity,
                PreviousStock = previousStock,
                NewStock = newStock,
                ReferenceGlobalId = payload.GlobalId,
                UserId = userId,
                DeviceId = tenant.DeviceId
            });

            var line = new SaleLine
            {
                GlobalId = linePayload.DetailGlobalId,
                ProductGlobalId = linePayload.ProductGlobalId,
                Quantity = linePayload.Quantity,
                UnitPriceCents = linePayload.UnitPriceCents,
                TotalCents = linePayload.TotalCents,
                FifoCostCents = linePayload.FifoCostCents
            };
            foreach (var lot in linePayload.Lots)
            {
                if (lot.Quantity <= 0 || lot.UnitCostCents < 0 || lot.TotalCostCents != checked((long)lot.Quantity * lot.UnitCostCents))
                    throw new ArgumentException("Invalid FIFO allocation.");
                line.Lots.Add(new SaleLotAllocation
                {
                    GlobalId = lot.GlobalId,
                    InventoryLotGlobalId = lot.LotGlobalId,
                    Quantity = lot.Quantity,
                    UnitCostCents = lot.UnitCostCents,
                    TotalCostCents = lot.TotalCostCents
                });
            }
            sale.Lines.Add(line);
        }

        if (sale.Lines.Sum(x => x.TotalCents) != payload.SubtotalCents)
            throw new ArgumentException("Sale subtotal does not equal the sum of lines.");
        if (sale.Lines.Sum(x => x.FifoCostCents) != payload.FifoCostCents)
            throw new ArgumentException("Sale FIFO cost does not equal the sum of lines.");

        _db.Sales.Add(sale);
    }

    private async Task ApplySaleCancellationAsync(
        SyncOperationDto operation,
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        var payload = Deserialize<SaleCancelSyncPayload>(operation);
        ValidateEnvelope(operation, payload.GlobalId);
        if (payload.DeviceGlobalId != tenant.DeviceGlobalId)
            throw new ArgumentException("Cancellation device does not match the authenticated device.");
        if (string.IsNullOrWhiteSpace(payload.Reason))
            throw new ArgumentException("Cancellation reason is required.");

        var sale = await _db.Sales
            .Include(x => x.Lines)
            .ThenInclude(x => x.Lots)
            .SingleOrDefaultAsync(
                x => x.BusinessId == tenant.BusinessId && x.GlobalId == payload.GlobalId,
                cancellationToken)
            ?? throw new InvalidOperationException($"Sale {payload.GlobalId} has not been synchronized yet.");
        if (sale.DeviceId != tenant.DeviceId || sale.BranchId != tenant.BranchId)
            throw new ArgumentException("Sale does not belong to the authenticated device.");
        if (sale.Status == "Cancelled") return;
        if (sale.Status != "Confirmed") throw new ArgumentException("Only confirmed sales can be cancelled.");

        var userId = await RequiredTenantUserIdAsync(payload.UserGlobalId, tenant.BusinessId, cancellationToken);
        foreach (var line in sale.Lines)
        {
            var previousStock = await _db.InventoryLots.AsNoTracking()
                .Where(x => x.BusinessId == tenant.BusinessId && x.BranchId == sale.BranchId && x.ProductGlobalId == line.ProductGlobalId && x.Active)
                .SumAsync(x => (int?)x.AvailableQuantity, cancellationToken) ?? 0;
            foreach (var allocation in line.Lots)
            {
                var lot = await _db.InventoryLots.SingleOrDefaultAsync(
                    x => x.BusinessId == tenant.BusinessId && x.GlobalId == allocation.InventoryLotGlobalId,
                    cancellationToken)
                    ?? throw new InvalidOperationException($"Inventory lot {allocation.InventoryLotGlobalId} is missing for cancellation.");
                if (lot.AvailableQuantity + allocation.Quantity > lot.InitialQuantity)
                    throw new ArgumentException("Cancellation would restore a lot beyond its original quantity.");
                lot.AvailableQuantity += allocation.Quantity;
            }
            _db.InventoryMovements.Add(new InventoryMovement
            {
                GlobalId = Guid.NewGuid(),
                BusinessId = tenant.BusinessId,
                BranchId = sale.BranchId,
                ProductGlobalId = line.ProductGlobalId,
                MovementDate = payload.CancelledAt,
                Type = "Cancellation",
                QuantityDelta = line.Quantity,
                PreviousStock = previousStock,
                NewStock = checked(previousStock + line.Quantity),
                ReferenceGlobalId = sale.GlobalId,
                UserId = userId,
                DeviceId = tenant.DeviceId,
                Notes = payload.Reason.Trim()
            });
        }
        sale.Status = "Cancelled";
        sale.CancelledAt = payload.CancelledAt;
        sale.CancellationReason = payload.Reason.Trim();
        sale.CancelledByUserId = userId;
    }


    private async Task<bool> IsPointOfSaleDeviceAsync(
        SyncTenantContext tenant,
        CancellationToken cancellationToken)
    {
        return await (
            from device in _db.Devices.AsNoTracking()
            join branch in _db.Branches.AsNoTracking() on device.BranchId equals branch.Id
            where device.Id == tenant.DeviceId &&
                  device.GlobalId == tenant.DeviceGlobalId &&
                  device.Active &&
                  device.Mode == PointOfSaleMode &&
                  branch.Id == tenant.BranchId &&
                  branch.BusinessId == tenant.BusinessId
            select device.Id)
            .AnyAsync(cancellationToken);
    }

    private async Task EnsureTenantActiveAsync(SyncTenantContext tenant, CancellationToken cancellationToken)
    {
        var valid = await (
            from business in _db.Businesses.AsNoTracking()
            join user in _db.Users.AsNoTracking() on business.Id equals user.BusinessId
            join branch in _db.Branches.AsNoTracking() on business.Id equals branch.BusinessId
            join device in _db.Devices.AsNoTracking() on branch.Id equals device.BranchId
            where business.Id == tenant.BusinessId && business.GlobalId == tenant.BusinessGlobalId && business.Active &&
                  user.Id == tenant.UserId && user.GlobalId == tenant.UserGlobalId && user.Active && user.Role == tenant.Role &&
                  branch.Id == tenant.BranchId && branch.GlobalId == tenant.BranchGlobalId && branch.Active &&
                  device.Id == tenant.DeviceId && device.GlobalId == tenant.DeviceGlobalId && device.Active
            select business.Id)
            .AnyAsync(cancellationToken);
        if (!valid) throw new UnauthorizedAccessException("Authenticated tenant context is no longer valid.");
    }


    private static void EnsureOperationAuthorized(SyncOperationDto operation, SyncTenantContext tenant)
    {
        if (tenant.Role == "Administrator") return;

        var allowed = tenant.Role switch
        {
            "Manager" => operation.EntityType is not ("Business" or "Branch" or "Device" or "User"),
            "Supervisor" => operation.EntityType is "Sale" or "CashSession" or "Purchase" or "Expense",
            "Seller" => operation.EntityType is "Sale" or "CashSession",
            _ => false
        };
        if (!allowed)
            throw new UnauthorizedAccessException("The authenticated role cannot synchronize this operation.");
    }

    private static void ValidateTransactionalContext(
        Guid businessGlobalId,
        Guid branchGlobalId,
        Guid deviceGlobalId,
        SyncTenantContext tenant)
    {
        RequireBusiness(businessGlobalId, tenant);
        if (branchGlobalId != tenant.BranchGlobalId)
            throw new ArgumentException("Operation branch does not match the authenticated branch.");
        if (deviceGlobalId != tenant.DeviceGlobalId)
            throw new ArgumentException("Operation device does not match the authenticated device.");
    }

    private static void RequireBusiness(Guid businessGlobalId, SyncTenantContext tenant)
    {
        if (businessGlobalId != tenant.BusinessGlobalId)
            throw new ArgumentException("Payload does not belong to the authenticated tenant.");
    }

    private async Task<long> RequiredTenantUserIdAsync(Guid userGlobalId, long businessId, CancellationToken cancellationToken)
    {
        var id = await _db.Users.AsNoTracking()
            .Where(x => x.BusinessId == businessId && x.GlobalId == userGlobalId && x.Active)
            .Select(x => x.Id)
            .SingleOrDefaultAsync(cancellationToken);
        if (id == 0) throw new InvalidOperationException($"Referenced user {userGlobalId} has not been synchronized yet.");
        return id;
    }

    private void AddChange(
        long businessId,
        string entityType,
        Guid entityGlobalId,
        string operation,
        long version,
        object payload)
    {
        _db.SyncChanges.Add(new SyncChange
        {
            BusinessId = businessId,
            EntityType = entityType,
            EntityGlobalId = entityGlobalId,
            Operation = operation,
            Version = version,
            PayloadJson = JsonSerializer.Serialize(payload, JsonOptions),
            CreatedAt = DateTimeOffset.UtcNow
        });
    }

    private static void EnsureExpectedVersion(
        SyncOperationDto operation,
        long? baseServerVersion,
        long currentVersion,
        object remotePayload)
    {
        if (operation.Operation != "Update") return;
        if (baseServerVersion is null)
            throw new ArgumentException("BaseServerVersion is required for catalog updates.");
        if (baseServerVersion.Value == currentVersion) return;
        throw new CatalogConflictException(
            currentVersion,
            JsonSerializer.Serialize(remotePayload, JsonOptions));
    }

    private static BusinessPullPayload BuildBusinessPayload(Business entity) =>
        new(entity.GlobalId, entity.Name, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static BranchPullPayload BuildBranchPayload(Branch entity, Guid businessGlobalId) =>
        new(entity.GlobalId, businessGlobalId, entity.Name, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static DevicePullPayload BuildDevicePayload(Device entity, Guid businessGlobalId, Guid branchGlobalId) =>
        new(entity.GlobalId, businessGlobalId, branchGlobalId, entity.Name, entity.Mode, entity.Active, entity.LastSyncAt, entity.ServerVersion);

    private static UserPullPayload BuildUserPayload(UserAccount entity, Guid businessGlobalId) =>
        new(entity.GlobalId, businessGlobalId, entity.Name, entity.Username, entity.PasswordHash, entity.PasswordSalt, entity.Role, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static CategoryPullPayload BuildCategoryPayload(Category entity, Guid businessGlobalId) =>
        new(entity.GlobalId, businessGlobalId, entity.Name, entity.Description, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static SupplierPullPayload BuildSupplierPayload(Supplier entity, Guid businessGlobalId) =>
        new(entity.GlobalId, businessGlobalId, entity.Name, entity.ContactName, entity.Phone, entity.Email, entity.Address, entity.Notes, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static ProductPullPayload BuildProductPayload(Product entity, Guid businessGlobalId) =>
        new(entity.GlobalId, businessGlobalId, entity.CategoryGlobalId, entity.Code, entity.Barcode, entity.Name, entity.Presentation, entity.SalePriceCents, entity.MinimumStock, entity.Active, entity.UpdatedAt, entity.ServerVersion);

    private static T Deserialize<T>(SyncOperationDto operation) where T : class =>
        operation.Payload.Deserialize<T>(JsonOptions) ?? throw new JsonException($"Invalid {operation.EntityType} payload.");

    private static void ValidateEnvelope(SyncOperationDto operation, Guid payloadGlobalId)
    {
        if (payloadGlobalId != operation.EntityGlobalId)
            throw new ArgumentException($"{operation.EntityType} global ID does not match sync envelope.");
    }

    private static string RequiredName(string value, string field)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException($"{field} is required.");
        return value.Trim();
    }

    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string SafeSyncError(Exception ex) => ex switch
    {
        DbUpdateException => "The server rejected the operation because it conflicts with persisted data.",
        UnauthorizedAccessException => "The authenticated tenant context is no longer valid.",
        _ => ex.Message
    };

    private sealed class CatalogConflictException(long remoteVersion, string remotePayloadJson) : Exception
    {
        public long RemoteVersion { get; } = remoteVersion;
        public string RemotePayloadJson { get; } = remotePayloadJson;
    }
}
