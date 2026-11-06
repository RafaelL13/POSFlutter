namespace Pos.Application;

// Input contains intent only; the server owns prices, stock, allocations and identity.
public sealed record WebCheckoutLine(Guid ProductGlobalId, int Quantity);
public sealed record WebCheckoutComboLine(Guid ComboGlobalId, long ExpectedServerVersion, int Quantity);
public sealed record WebCheckoutPayment(string Method, long AmountCents);
public sealed record WebCheckoutRequest(
    Guid IdempotencyKey,
    IReadOnlyList<WebCheckoutLine> Lines,
    IReadOnlyList<WebCheckoutPayment> Payments,
    long? ReceivedCashCents = null,
    IReadOnlyList<WebCheckoutComboLine>? Combos = null);
public sealed record WebCheckoutResult(Guid SaleGlobalId, string Folio, long TotalCents,
    long FifoCostCents, bool AlreadyProcessed, DateTimeOffset SaleDateTime);
