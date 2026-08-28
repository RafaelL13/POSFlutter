enum Capability {
  posAccess,

  saleCreate,
  saleHistory,
  saleCancel,
  saleDiscount,

  cashOpen,
  cashRead,
  cashClose,
  cashCloseWithDifference,
  cashWithdrawal,

  purchaseRead,
  purchaseCreate,

  expenseRead,
  expenseCreate,

  productRead,
  productWrite,
  productPriceChange,

  categoryRead,
  categoryWrite,

  supplierRead,
  supplierWrite,

  inventoryAvailabilityRead,
  inventoryLotsRead,
  inventoryAdjust,

  reportsOperational,
  reportsFinancial,

  usersRead,
  usersWrite,

  devicesRead,
  devicesWrite,

  businessRead,
  businessWrite,

  branchesRead,
  branchesWrite,

  enrollment,

  backupCreate,
  backupRestore,

  cloudAdminRead,

  syncPush,
  syncPull,

  viewPurchaseCost,
  viewFifoHistoricalCost,
  viewProfit,
  viewMargin,
  viewSupplierPrice,
  viewExpenses,
  viewInventoryValue,
}

extension CapabilityPolicyMetadata on Capability {
  bool get blockedByAdminReadOnly {
    return switch (this) {
      Capability.saleCreate ||
      Capability.saleCancel ||
      Capability.saleDiscount ||
      Capability.cashOpen ||
      Capability.cashClose ||
      Capability.cashCloseWithDifference ||
      Capability.cashWithdrawal ||
      Capability.purchaseCreate ||
      Capability.expenseCreate ||
      Capability.productWrite ||
      Capability.productPriceChange ||
      Capability.categoryWrite ||
      Capability.supplierWrite ||
      Capability.inventoryAdjust ||
      Capability.usersWrite ||
      Capability.devicesWrite ||
      Capability.businessWrite ||
      Capability.branchesWrite ||
      Capability.enrollment ||
      Capability.backupRestore ||
      Capability.syncPush => true,
      _ => false,
    };
  }
}
