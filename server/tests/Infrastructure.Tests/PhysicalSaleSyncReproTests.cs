using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class PhysicalSaleSyncReproTests
{
    [Fact]
    public async Task Physical_offline_sale_payload_is_applied()
    {
        await using var test = await TestDatabase.CreateAsync();

        var payloadJson = Encoding.UTF8.GetString(
            Convert.FromBase64String("eyJnbG9iYWxJZCI6IjAxYTA5Y2ExLTUyNzctNzk3Ni05ZmFiLTJiN2NiMDE0ZTY5NCIsImlkZW1wb3RlbmN5S2V5IjoiMDFhMDljYTEtNTI3OC03NmYyLTlmNWEtNWNjOTFkOTBiZGM3IiwiYnVzaW5lc3NHbG9iYWxJZCI6IjAxYTA5ODlkLWQ5NDEtNzI2MS05YzY0LWFkMzE0Zjk1NWVhNCIsImJyYW5jaEdsb2JhbElkIjoiMDFhMDk4OWQtZDk0ZC03ZmU1LTg5NmYtOTJiN2ExNDY2ZjgxIiwiZGV2aWNlR2xvYmFsSWQiOiIwMWEwOTg5ZC1kOTRlLTdjYzYtYTg2Zi1kZGM1NzI2NTkzMjMiLCJ1c2VyR2xvYmFsSWQiOiIwMWEwOTg5ZC1kOTRlLTc4OTMtOGI0MS03YmNkYWE4MDk4ODIiLCJmb2xpbyI6IlYtMTc4OTMzNDIxMzUxNiIsInNhbGVEYXRlVGltZSI6IjIwMjYtMDktMTNUMjE6MTY6NTMuMjM5MjU4WiIsInN1YnRvdGFsQ2VudHMiOjEyNTAwLCJkaXNjb3VudENlbnRzIjowLCJ0b3RhbENlbnRzIjoxMjUwMCwiZmlmb0Nvc3RDZW50cyI6MTE1MDAsImdyb3NzUHJvZml0Q2VudHMiOjEwMDAsInBheW1lbnRNZXRob2QiOiJDYXNoIiwicmVjZWl2ZWRDZW50cyI6MTUwMDAsImNoYW5nZUNlbnRzIjoyNTAwLCJwYXltZW50cyI6W3siZ2xvYmFsSWQiOiIwMWEwOWNhMS01MzFkLTcyMzQtODI4Mi1lNzY1ODFlMzhiMGUiLCJtZXRob2QiOiJDYXNoIiwiYW1vdW50Q2VudHMiOjEyNTAwfV0sImxpbmVzIjpbeyJkZXRhaWxHbG9iYWxJZCI6IjAxYTA5Y2ExLTUzNWEtN2U3Ni05YmMyLTdlZmY2MTcyYTQ0MSIsInByb2R1Y3RHbG9iYWxJZCI6IjAxYTA5OGE0LTQ4Y2MtNzY5Zi1hNTlmLTM1MDFkNjA1ZjUzZSIsInF1YW50aXR5IjoxLCJ1bml0UHJpY2VDZW50cyI6MTI1MDAsImRpc2NvdW50Q2VudHMiOjAsInRvdGFsQ2VudHMiOjEyNTAwLCJmaWZvQ29zdENlbnRzIjoxMTUwMCwibG90cyI6W3siaW52ZW50b3J5TG90R2xvYmFsSWQiOiIwMWEwOThhNS03N2RlLTdiYzEtOGI1Zi0wNDdjMTU4OTA3YmYiLCJxdWFudGl0eSI6MSwidW5pdENvc3RDZW50cyI6MTE1MDAsInRvdGFsQ29zdENlbnRzIjoxMTUwMH1dfV19"));

        using var payloadDocument = JsonDocument.Parse(payloadJson);
        var root = payloadDocument.RootElement;

        var businessGlobalId =
            root.GetProperty("businessGlobalId").GetGuid();
        var branchGlobalId =
            root.GetProperty("branchGlobalId").GetGuid();
        var deviceGlobalId =
            root.GetProperty("deviceGlobalId").GetGuid();
        var userGlobalId =
            root.GetProperty("userGlobalId").GetGuid();

        var line = root.GetProperty("lines")[0];
        var productGlobalId =
            line.GetProperty("productGlobalId").GetGuid();
        var lotPayload = line.GetProperty("lots")[0];
        var lotGlobalId =
            lotPayload.GetProperty("inventoryLotGlobalId").GetGuid();
        var lotCost =
            lotPayload.GetProperty("unitCostCents").GetInt64();

        var now = DateTimeOffset.UtcNow;

        var business = new Business
        {
            GlobalId = businessGlobalId,
            Name = "Physical repro business",
            Active = true,
            CreatedAt = now,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Businesses.Add(business);
        await test.Db.SaveChangesAsync();

        var branch = new Branch
        {
            GlobalId = branchGlobalId,
            BusinessId = business.Id,
            Name = "Principal",
            Active = true,
            CreatedAt = now,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.Branches.Add(branch);
        await test.Db.SaveChangesAsync();

        var device = new Device
        {
            GlobalId = deviceGlobalId,
            BranchId = branch.Id,
            Name = "Physical tablet",
            Mode = "PointOfSale",
            Active = true,
            CreatedAt = now,
            LastSyncAt = now,
            ServerVersion = 1
        };

        var user = new UserAccount
        {
            GlobalId = userGlobalId,
            BusinessId = business.Id,
            Name = "Physical actor",
            Username = "physical_repro",
            PasswordHash = "test",
            PasswordSalt = "test",
            Role = "Administrator",
            Active = true,
            CreatedAt = now,
            UpdatedAt = now,
            ServerVersion = 1
        };

        var product = new Product
        {
            GlobalId = productGlobalId,
            BusinessId = business.Id,
            Code = "PHYSICAL",
            Name = "Physical product",
            Presentation = "Unit",
            SalePriceCents =
                line.GetProperty("unitPriceCents").GetInt64(),
            MinimumStock = 0,
            Active = true,
            UpdatedAt = now,
            ServerVersion = 1
        };

        test.Db.AddRange(device, user, product);
        await test.Db.SaveChangesAsync();

        var lot = new InventoryLot
        {
            GlobalId = lotGlobalId,
            BusinessId = business.Id,
            BranchId = branch.Id,
            ProductGlobalId = productGlobalId,
            EntryDate = now,
            InitialQuantity = 50,
            AvailableQuantity = 50,
            UnitCostCents = lotCost,
            Active = true,
            CreatedAt = now
        };

        test.Db.InventoryLots.Add(lot);
        await test.Db.SaveChangesAsync();

        var context = new SyncTenantContext(
            business.Id,
            business.GlobalId,
            branch.Id,
            branch.GlobalId,
            device.Id,
            device.GlobalId,
            user.Id,
            user.GlobalId,
            user.Role,
            device.Mode);

        using var operationDocument = JsonDocument.Parse(payloadJson);

        var operation = new SyncOperationDto(
            Guid.Parse("01a09ca1-538d-79d9-9c34-8c6db4a0ccae"),
            "Sale",
            root.GetProperty("globalId").GetGuid(),
            "Create",
            2,
            operationDocument.RootElement.Clone());

        var response = await new SyncService(test.Db).PushAsync(
            new SyncPushRequest([operation]),
            context,
            TestContext.Current.CancellationToken);

        var result = Assert.Single(response.Results);

        Assert.True(
            result.Status == "Applied",
            $"STATUS={result.Status}; ERROR_CODE={result.ErrorCode}; ERROR={result.Error}");

        var storedSale = await test.Db.Sales
            .Include(x => x.Lines)
            .ThenInclude(x => x.Lots)
            .Include(x => x.Payments)
            .SingleAsync(x =>
                x.GlobalId == root.GetProperty("globalId").GetGuid());

        Assert.NotEmpty(storedSale.Lines);
        Assert.NotEmpty(storedSale.Payments);
        Assert.Equal(
            49,
            (await test.Db.InventoryLots.SingleAsync(
                x => x.GlobalId == lotGlobalId)).AvailableQuantity);
    }
}