namespace Pos.Infrastructure;

/// <summary>
/// Explicit protocol opt-in. Never infer support from application version or JWT alone.
/// </summary>
public static class WebSaleSyncCapability
{
    public const string Header = "X-POSFlutter-Sync-Capability";
    public const string Value = "WebSaleInventoryV1";

    public static bool IsSupported(string? value) =>
        string.Equals(value, Value, StringComparison.Ordinal);
}
