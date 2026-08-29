namespace Pos.Application;

public enum BackendReadCapability
{
    ProductsRead,
    CategoriesRead,
    SuppliersRead,
    SalesRead,
    PurchasesRead,
    InventoryAvailabilityRead,
    InventoryLotsRead,
    ExpensesRead,
    CashRead,
    UsersRead,
    DevicesRead,
    BusinessRead,
    BranchesRead,
    FinancialReportsRead,
    ViewPurchaseCost,
    ViewFifoHistoricalCost,
    ViewProfit,
    ViewMargin,
    ViewSupplierPrice,
    ViewExpenses,
    ViewInventoryValue
}

public enum BackendReadPermission
{
    None,
    OwnOnly,
    Branch,
    Read
}

public static class BackendReadAuthorization
{
    public const int AuthorizationPolicyVersion = 1;

    public static string PolicyName(BackendReadCapability capability) =>
        $"Read:{capability}";

    public static BackendReadPermission PermissionFor(
        string? role,
        string? deviceMode,
        BackendReadCapability capability)
    {
        if (deviceMode is not ("PointOfSale" or "AdminReadOnly"))
        {
            return BackendReadPermission.None;
        }

        return role switch
        {
            "Administrator" => BackendReadPermission.Read,
            "Manager" => Manager(capability),
            "Supervisor" => Supervisor(capability),
            "Seller" => Seller(capability),
            _ => BackendReadPermission.None
        };
    }

    public static BackendReadPermission Require(
        SyncTenantContext tenant,
        BackendReadCapability capability)
    {
        var permission = PermissionFor(tenant.Role, tenant.DeviceMode, capability);
        if (permission == BackendReadPermission.None)
        {
            throw new UnauthorizedAccessException(
                $"Read capability {capability} is not allowed.");
        }

        return permission;
    }

    private static BackendReadPermission Manager(BackendReadCapability capability) =>
        capability switch
        {
            _ => BackendReadPermission.Read
        };

    private static BackendReadPermission Supervisor(BackendReadCapability capability) =>
        capability switch
        {
            BackendReadCapability.ProductsRead or
            BackendReadCapability.CategoriesRead or
            BackendReadCapability.SalesRead or
            BackendReadCapability.PurchasesRead or
            BackendReadCapability.InventoryAvailabilityRead or
            BackendReadCapability.InventoryLotsRead or
            BackendReadCapability.ExpensesRead or
            BackendReadCapability.CashRead or
            BackendReadCapability.BranchesRead => BackendReadPermission.Branch,
            BackendReadCapability.ViewExpenses => BackendReadPermission.Read,
            _ => BackendReadPermission.None
        };

    private static BackendReadPermission Seller(BackendReadCapability capability) =>
        capability switch
        {
            BackendReadCapability.ProductsRead or
            BackendReadCapability.CategoriesRead or
            BackendReadCapability.InventoryAvailabilityRead => BackendReadPermission.Branch,
            BackendReadCapability.SalesRead or
            BackendReadCapability.CashRead => BackendReadPermission.OwnOnly,
            _ => BackendReadPermission.None
        };
}
