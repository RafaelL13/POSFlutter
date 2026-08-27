namespace Pos.Application;

public sealed record ReportPeriod(DateTimeOffset From, DateTimeOffset ToExclusive);
public sealed record ReportPage<T>(int Page,int PageSize,long TotalCount,IReadOnlyList<T> Items);

public sealed record RemoteSummaryReport(
    DateTimeOffset From,
    DateTimeOffset ToExclusive,
    long GrossSalesCents,
    long NetSalesCents,
    int SalesCount,
    int UnitsSold,
    long AverageTicketCents,
    long FifoCostCents,
    long GrossProfitCents,
    double GrossMarginPercent,
    long ExpensesCents,
    long ResultAfterExpensesCents,
    int CancelledSalesCount,
    long CancelledSalesCents,
    double CancellationRatePercent,
    int InventoryUnits,
    long InventoryValueCents);

public sealed record SalesPeriodRow(
    string Period,
    DateTimeOffset PeriodStart,
    DateTimeOffset PeriodEndExclusive,
    long SalesCents,
    int Transactions,
    int Units,
    long FifoCostCents,
    long GrossProfitCents,
    double MarginPercent);

public sealed record SaleReportDetailRow(
    Guid GlobalId,
    string Folio,
    DateTimeOffset SaleDateTime,
    string UserName,
    string PaymentMethod,
    string Status,
    int Units,
    long TotalCents,
    long FifoCostCents,
    long GrossProfitCents);

public sealed record ProductPerformanceRow(
    Guid ProductGlobalId,
    string Code,
    string Name,
    string? CategoryName,
    int Units,
    long RevenueCents,
    long FifoCostCents,
    long GrossProfitCents,
    double MarginPercent,
    int Transactions);

public sealed record CategoryPerformanceRow(
    string Category,
    int Units,
    long RevenueCents,
    long FifoCostCents,
    long GrossProfitCents,
    double MarginPercent,
    double RevenueSharePercent);

public sealed record UserPerformanceRow(
    Guid UserGlobalId,
    string Name,
    string Role,
    int SalesCount,
    int Units,
    long RevenueCents,
    long AverageTicketCents,
    int CancelledSalesCount,
    long CancelledSalesCents);

public sealed record PurchaseReportRow(
    string GroupKey,
    string GroupName,
    int Purchases,
    int Units,
    long AmountCents,
    long AverageUnitCostCents);

public sealed record SupplierPerformanceRow(
    Guid SupplierGlobalId,
    string Name,
    int Purchases,
    int Units,
    long AmountCents,
    int ProductsSupplied,
    DateTimeOffset? LastPurchaseAt);

public sealed record InventoryReportRow(
    Guid ProductGlobalId,
    string Code,
    string Name,
    int Stock,
    int MinimumStock,
    int ActiveLots,
    long RemainingFifoCostCents,
    long AverageUnitCostCents,
    DateTimeOffset? LastEntryAt,
    DateTimeOffset? LastSaleAt);

public sealed record ExpenseBreakdownRow(string Group,long AmountCents,int Expenses);
public sealed record ExpenseDetailRow(Guid GlobalId,DateTimeOffset ExpenseDate,string Concept,string? Category,string PaymentMethod,string UserName,long AmountCents);
public sealed record ExpenseReportResponse(long TotalCents,int Expenses,IReadOnlyList<ExpenseBreakdownRow> Breakdown,ReportPage<ExpenseDetailRow> Details);

public sealed record CashReportRow(
    Guid SessionGlobalId,
    string UserName,
    DateTimeOffset OpenedAt,
    DateTimeOffset? ClosedAt,
    string Status,
    long OpeningBalanceCents,
    long CashSalesCents,
    long CashExpensesCents,
    long CalculatedExpectedCashCents,
    long? RecordedExpectedCashCents,
    long? CountedCashCents,
    long? DifferenceCents);

public sealed record PaymentMethodReportRow(string PaymentMethod,int Transactions,long AmountCents,double Percentage);

public sealed record CancellationReportRow(
    Guid SaleGlobalId,
    string Folio,
    DateTimeOffset SaleDateTime,
    DateTimeOffset? CancelledAt,
    string UserName,
    string? Reason,
    int Units,
    long AmountCents);
public sealed record CancellationReportResponse(
    int OriginalSalesCount,
    long OriginalSalesCents,
    int CancelledSalesCount,
    long CancelledSalesCents,
    int CancelledUnits,
    double CancellationRatePercent,
    ReportPage<CancellationReportRow> Details);

public sealed record ProductTrendRow(
    Guid ProductGlobalId,
    string Code,
    string Name,
    int CurrentUnits,
    int PreviousUnits,
    long CurrentRevenueCents,
    long PreviousRevenueCents,
    double UnitsChangePercent,
    double RevenueChangePercent,
    string Trend);
