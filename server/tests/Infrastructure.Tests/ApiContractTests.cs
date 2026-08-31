using System.Text.Json;
using Pos.Application;

namespace Pos.Infrastructure.Tests;

public sealed class ApiContractTests
{
    [Fact]
    public void Bootstrap_contract_has_unambiguous_web_json_property_names()
    {
        var request = new BootstrapRequest(
            Guid.NewGuid(), "Business", Guid.NewGuid(), "Branch",
            Guid.NewGuid(), "Device", Guid.NewGuid(), "Display name",
            "username", "hash", "salt");
        var json = JsonSerializer.Serialize(
            request,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var names = JsonDocument.Parse(json).RootElement
            .EnumerateObject().Select(property => property.Name).ToArray();

        Assert.Contains("userDisplayName", names);
        Assert.Contains("username", names);
        Assert.Equal(names.Length, names.Distinct(StringComparer.OrdinalIgnoreCase).Count());
    }
}
