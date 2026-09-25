using System.Security.Cryptography;
using System.Text;

namespace Pos.Api;

internal static class CentralInventoryAuthentication
{
    internal const string HeaderName = "X-Central-Inventory-Key";
    internal const string ConfigurationKey = "CentralInventory:ApiKey";

    internal static bool IsAuthorized(
        HttpRequest request,
        IConfiguration configuration)
    {
        var configuredKey = configuration[ConfigurationKey];

        if (string.IsNullOrWhiteSpace(configuredKey))
        {
            return false;
        }

        if (!request.Headers.TryGetValue(HeaderName, out var suppliedValues))
        {
            return false;
        }

        var suppliedKey = suppliedValues.ToString();

        if (string.IsNullOrWhiteSpace(suppliedKey))
        {
            return false;
        }

        var configuredBytes = Encoding.UTF8.GetBytes(configuredKey);
        var suppliedBytes = Encoding.UTF8.GetBytes(suppliedKey);

        return configuredBytes.Length == suppliedBytes.Length &&
               CryptographicOperations.FixedTimeEquals(
                   configuredBytes,
                   suppliedBytes);
    }
}