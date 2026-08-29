using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure.Tests;

public sealed class RemoteReportServiceTests
{
    private static SyncTenantContext Context((Business Business,Branch Branch,Device Device,UserAccount User) tenant) =>
        new(tenant.Business.Id,tenant.Business.GlobalId,tenant.Branch.Id,tenant.Branch.GlobalId,tenant.Device.Id,tenant.Device.GlobalId,tenant.User.Id,tenant.User.GlobalId,tenant.User.Role,tenant.Device.Mode);

    private static ReportPeriod Period(DateTimeOffset center,int days=2) => new(center.AddDays(-days),center.AddDays(days));

    private static async Task<Product> AddProductAsync(SqlServerTestDatabase test,Business business,string code,string name)
    {
        var product = new Product { GlobalId = Guid.NewGuid(),BusinessId = business.Id,Code = code,Name = name,UpdatedAt = DateTimeOffset.UtcNow,SalePriceCents = 1000 };
        test.Db.Products.Add(product); await test.Db.SaveChangesAsync(); return product;
    }

    private static async Task<Sale> AddSaleAsync(SqlServerTestDatabase test,(Business Business,Branch Branch,Device Device,UserAccount User) tenant,Product product,DateTimeOffset date,long totalCents=1000,int quantity=1,long allocationCostCents=400,string status="Confirmed",string paymentMethod="Cash")
    {
        var sale = new Sale { GlobalId = Guid.NewGuid(),IdempotencyKey = Guid.NewGuid(),BusinessId = tenant.Business.Id,BranchId = tenant.Branch.Id,DeviceId = tenant.Device.Id,UserId = tenant.User.Id,Folio = Guid.NewGuid().ToString("N")[..8],SaleDateTime = date,SubtotalCents = totalCents,TotalCents = totalCents,FifoCostCents = allocationCostCents,GrossProfitCents = totalCents - allocationCostCents,PaymentMethod = paymentMethod,Status = status,CreatedAt = date,CancelledAt = status == "Cancelled" ? date.AddMinutes(10) : null,CancellationReason = status == "Cancelled" ? "Test" : null };
        test.Db.Sales.Add(sale); await test.Db.SaveChangesAsync();
        var line = new SaleLine { GlobalId = Guid.NewGuid(),SaleId = sale.Id,ProductGlobalId = product.GlobalId,Quantity = quantity,UnitPriceCents = quantity == 0 ? 0 : totalCents / quantity,TotalCents = totalCents,FifoCostCents = allocationCostCents };
        test.Db.SaleLines.Add(line); await test.Db.SaveChangesAsync();
        test.Db.SaleLotAllocations.Add(new SaleLotAllocation { GlobalId = Guid.NewGuid(),SaleLineId = line.Id,InventoryLotGlobalId = Guid.NewGuid(),Quantity = quantity,UnitCostCents = quantity == 0 ? 0 : allocationCostCents / quantity,TotalCostCents = allocationCostCents });
        await test.Db.SaveChangesAsync(); return sale;
    }

    [Fact]
    public async Task Summary_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("RA"); var b = await test.SeedTenantAsync("RB");
        var pa = await AddProductAsync(test,a.Business,"A","A"); var pb = await AddProductAsync(test,b.Business,"B","B");
        await AddSaleAsync(test,a,pa,now,totalCents:1000,allocationCostCents:300);
        await AddSaleAsync(test,b,pb,now,totalCents:9000,allocationCostCents:100);
        var result = await new RemoteReportService(test.Db).SummaryAsync(Context(a),Period(now),CancellationToken.None);
        Assert.Equal(1000,result.NetSalesCents); Assert.Equal(300,result.FifoCostCents); Assert.Equal(1,result.SalesCount);
    }

    [Fact]
    public async Task Sales_series_respects_tenant_and_period()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("SA"); var b = await test.SeedTenantAsync("SB");
        var pa = await AddProductAsync(test,a.Business,"A","A"); var pb = await AddProductAsync(test,b.Business,"B","B");
        await AddSaleAsync(test,a,pa,now,totalCents:1200); await AddSaleAsync(test,a,pa,now.AddDays(-20),totalCents:5000); await AddSaleAsync(test,b,pb,now,totalCents:8000);
        var rows = await new RemoteReportService(test.Db).SalesAsync(Context(a),Period(now),"day",CancellationToken.None);
        Assert.Equal(1200,rows.Sum(x => x.SalesCents)); Assert.Equal(1,rows.Sum(x => x.Transactions));
    }

    [Fact]
    public async Task Product_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("PA"); var b = await test.SeedTenantAsync("PB");
        var pa = await AddProductAsync(test,a.Business,"A","Alpha"); var pb = await AddProductAsync(test,b.Business,"B","Beta");
        await AddSaleAsync(test,a,pa,now,totalCents:1500); await AddSaleAsync(test,b,pb,now,totalCents:9500);
        var rows = await new RemoteReportService(test.Db).ProductsAsync(Context(a),Period(now),"revenue",true,20,CancellationToken.None);
        Assert.Single(rows); Assert.Equal(pa.GlobalId,rows[0].ProductGlobalId); Assert.Equal(1500,rows[0].RevenueCents);
    }

    [Fact]
    public async Task Inventory_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var a = await test.SeedTenantAsync("IA"); var b = await test.SeedTenantAsync("IB"); var pa = await AddProductAsync(test,a.Business,"A","Alpha"); var pb = await AddProductAsync(test,b.Business,"B","Beta");
        test.Db.InventoryLots.AddRange(
            new InventoryLot { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,ProductGlobalId = pa.GlobalId,EntryDate = DateTimeOffset.UtcNow,InitialQuantity = 5,AvailableQuantity = 3,UnitCostCents = 100,CreatedAt = DateTimeOffset.UtcNow },
            new InventoryLot { GlobalId = Guid.NewGuid(),BusinessId = b.Business.Id,BranchId = b.Branch.Id,ProductGlobalId = pb.GlobalId,EntryDate = DateTimeOffset.UtcNow,InitialQuantity = 99,AvailableQuantity = 99,UnitCostCents = 999,CreatedAt = DateTimeOffset.UtcNow });
        await test.Db.SaveChangesAsync();
        var rows = await new RemoteReportService(test.Db).InventoryAsync(Context(a),CancellationToken.None);
        Assert.Single(rows); Assert.Equal(3,rows[0].Stock); Assert.Equal(300,rows[0].RemainingFifoCostCents);
    }

    [Fact]
    public async Task Purchase_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("BUYA"); var b = await test.SeedTenantAsync("BUYB");
        var supplierA = new Supplier { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,Name = "Supplier A",UpdatedAt = now }; var supplierB = new Supplier { GlobalId = Guid.NewGuid(),BusinessId = b.Business.Id,Name = "Supplier B",UpdatedAt = now };
        test.Db.Suppliers.AddRange(supplierA,supplierB); await test.Db.SaveChangesAsync();
        test.Db.Purchases.AddRange(
            new Purchase { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,DeviceId = a.Device.Id,UserId = a.User.Id,SupplierGlobalId = supplierA.GlobalId,PurchaseDate = now,TotalCents = 2000,CreatedAt = now },
            new Purchase { GlobalId = Guid.NewGuid(),BusinessId = b.Business.Id,BranchId = b.Branch.Id,DeviceId = b.Device.Id,UserId = b.User.Id,SupplierGlobalId = supplierB.GlobalId,PurchaseDate = now,TotalCents = 9000,CreatedAt = now });
        await test.Db.SaveChangesAsync();
        var rows = await new RemoteReportService(test.Db).PurchasesAsync(Context(a),Period(now),"supplier",CancellationToken.None);
        Assert.Single(rows); Assert.Equal(2000,rows[0].AmountCents);
    }

    [Fact]
    public async Task Expense_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("EA"); var b = await test.SeedTenantAsync("EB");
        test.Db.Expenses.AddRange(
            new Expense { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,DeviceId = a.Device.Id,UserId = a.User.Id,ExpenseDate = now,Concept = "A",AmountCents = 400,CreatedAt = now },
            new Expense { GlobalId = Guid.NewGuid(),BusinessId = b.Business.Id,BranchId = b.Branch.Id,DeviceId = b.Device.Id,UserId = b.User.Id,ExpenseDate = now,Concept = "B",AmountCents = 9000,CreatedAt = now });
        await test.Db.SaveChangesAsync();
        var result = await new RemoteReportService(test.Db).ExpensesAsync(Context(a),Period(now),"category",1,50,CancellationToken.None);
        Assert.Equal(400,result.TotalCents); Assert.Single(result.Details.Items);
    }

    [Fact]
    public async Task Cash_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("CA"); var b = await test.SeedTenantAsync("CB");
        test.Db.CashSessions.AddRange(
            new CashSession { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,DeviceId = a.Device.Id,UserId = a.User.Id,OpenedAt = now.AddHours(-1),OpeningBalanceCents = 500,Status = "Open",UpdatedAt = now },
            new CashSession { GlobalId = Guid.NewGuid(),BusinessId = b.Business.Id,BranchId = b.Branch.Id,DeviceId = b.Device.Id,UserId = b.User.Id,OpenedAt = now.AddHours(-1),OpeningBalanceCents = 9000,Status = "Open",UpdatedAt = now });
        await test.Db.SaveChangesAsync();
        var result = await new RemoteReportService(test.Db).CashAsync(Context(a),Period(now),1,50,CancellationToken.None);
        Assert.Equal(1,result.TotalCount); Assert.Equal(500,result.Items[0].OpeningBalanceCents);
    }

    [Fact]
    public async Task User_report_is_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("UA"); var b = await test.SeedTenantAsync("UB");
        var pa = await AddProductAsync(test,a.Business,"A","A"); var pb = await AddProductAsync(test,b.Business,"B","B");
        await AddSaleAsync(test,a,pa,now,totalCents:1111); await AddSaleAsync(test,b,pb,now,totalCents:9999);
        var rows = await new RemoteReportService(test.Db).UsersAsync(Context(a),Period(now),CancellationToken.None);
        Assert.Single(rows); Assert.Equal(a.User.GlobalId,rows[0].UserGlobalId); Assert.Equal(1111,rows[0].RevenueCents);
    }

    [Fact]
    public async Task Cancelled_sales_are_reported_without_double_counting_net_sales()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var a = await test.SeedTenantAsync("CAN"); var p = await AddProductAsync(test,a.Business,"P","Product");
        await AddSaleAsync(test,a,p,now,totalCents:1000,status:"Confirmed"); await AddSaleAsync(test,a,p,now.AddMinutes(1),totalCents:2000,status:"Cancelled");
        var summary = await new RemoteReportService(test.Db).SummaryAsync(Context(a),Period(now),CancellationToken.None);
        Assert.Equal(3000,summary.GrossSalesCents); Assert.Equal(1000,summary.NetSalesCents); Assert.Equal(2000,summary.CancelledSalesCents); Assert.Equal(1,summary.CancelledSalesCount);
    }

    [Fact]
    public async Task Historical_cost_comes_from_sale_lot_allocations()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var a = await test.SeedTenantAsync("FIFO"); var p = await AddProductAsync(test,a.Business,"P","Product");
        var sale = await AddSaleAsync(test,a,p,now,totalCents:1000,allocationCostCents:200);
        sale.FifoCostCents = 9999; var line = test.Db.SaleLines.Single(x => x.SaleId == sale.Id); line.FifoCostCents = 8888; p.SalePriceCents = 7777; await test.Db.SaveChangesAsync();
        var summary = await new RemoteReportService(test.Db).SummaryAsync(Context(a),Period(now),CancellationToken.None);
        Assert.Equal(200,summary.FifoCostCents); Assert.Equal(800,summary.GrossProfitCents);
    }

    [Fact]
    public async Task Inventory_value_uses_remaining_lot_quantities()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var a = await test.SeedTenantAsync("VAL"); var p = await AddProductAsync(test,a.Business,"P","Product"); var now = DateTimeOffset.UtcNow;
        test.Db.InventoryLots.AddRange(
            new InventoryLot { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,ProductGlobalId = p.GlobalId,EntryDate = now.AddDays(-2),InitialQuantity = 10,AvailableQuantity = 3,UnitCostCents = 100,CreatedAt = now },
            new InventoryLot { GlobalId = Guid.NewGuid(),BusinessId = a.Business.Id,BranchId = a.Branch.Id,ProductGlobalId = p.GlobalId,EntryDate = now.AddDays(-1),InitialQuantity = 5,AvailableQuantity = 5,UnitCostCents = 120,CreatedAt = now });
        await test.Db.SaveChangesAsync();
        var row = Assert.Single(await new RemoteReportService(test.Db).InventoryAsync(Context(a),CancellationToken.None));
        Assert.Equal(8,row.Stock); Assert.Equal(900,row.RemainingFifoCostCents);
    }

    [Fact]
    public async Task Trend_compares_immediately_previous_equal_period()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var a = await test.SeedTenantAsync("TREND"); var p = await AddProductAsync(test,a.Business,"P","Product");
        var current = new ReportPeriod(now.AddDays(-2),now); var previousDate = now.AddDays(-3); var currentDate = now.AddDays(-1);
        await AddSaleAsync(test,a,p,previousDate,totalCents:2000,quantity:2); await AddSaleAsync(test,a,p,currentDate,totalCents:1000,quantity:1);
        var row = Assert.Single(await new RemoteReportService(test.Db).ProductTrendsAsync(Context(a),current,20,CancellationToken.None));
        Assert.Equal(-50,row.RevenueChangePercent); Assert.Equal("Declining",row.Trend);
    }

    [Fact]
    public async Task Sale_details_are_paginated()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var a = await test.SeedTenantAsync("PAGE"); var p = await AddProductAsync(test,a.Business,"P","Product");
        await AddSaleAsync(test,a,p,now.AddMinutes(-3)); await AddSaleAsync(test,a,p,now.AddMinutes(-2)); await AddSaleAsync(test,a,p,now.AddMinutes(-1));
        var page = await new RemoteReportService(test.Db).SaleDetailsAsync(Context(a),Period(now),2,2,CancellationToken.None);
        Assert.Equal(3,page.TotalCount); Assert.Single(page.Items); Assert.Equal(2,page.Page); Assert.Equal(2,page.PageSize);
    }

    [Fact]
    public async Task AdminReadOnly_device_can_read_remote_reports()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var tenant = await test.SeedTenantAsync("READ",mode:"AdminReadOnly");
        var result = await new RemoteReportService(test.Db).SummaryAsync(Context(tenant),Period(now),CancellationToken.None);
        Assert.Equal(0,result.NetSalesCents); Assert.Equal("AdminReadOnly",tenant.Device.Mode);
    }

    [Fact]
    public async Task Low_performance_no_sales_is_explicit_and_includes_zero_sale_product()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow; var tenant = await test.SeedTenantAsync("LOW");
        var sold = await AddProductAsync(test,tenant.Business,"SOLD","Sold"); var idle = await AddProductAsync(test,tenant.Business,"IDLE","Idle"); await AddSaleAsync(test,tenant,sold,now,totalCents:1000);
        var rows = await new RemoteReportService(test.Db).LowPerformanceAsync(Context(tenant),Period(now),"no-sales",20,CancellationToken.None);
        var row = Assert.Single(rows); Assert.Equal(idle.GlobalId,row.ProductGlobalId); Assert.Equal(0,row.Transactions);
    }

    [Fact]
    public async Task Global_id_filters_remain_tenant_scoped()
    {
        await using var test = await SqlServerTestDatabase.CreateAsync(); var now = DateTimeOffset.UtcNow;
        var a = await test.SeedTenantAsync("FILTERA"); var b = await test.SeedTenantAsync("FILTERB");
        var productA = await AddProductAsync(test,a.Business,"A","Product A"); var productB = await AddProductAsync(test,b.Business,"B","Product B");
        await AddSaleAsync(test,a,productA,now,totalCents:1200); await AddSaleAsync(test,b,productB,now,totalCents:9900);
        var service = new RemoteReportService(test.Db);
        var own = await service.ProductsAsync(Context(a),Period(now),"revenue",true,20,CancellationToken.None,productA.GlobalId,null);
        var foreign = await service.ProductsAsync(Context(a),Period(now),"revenue",true,20,CancellationToken.None,productB.GlobalId,null);
        var foreignUserSales = await service.SalesAsync(Context(a),Period(now),"day",CancellationToken.None,b.User.GlobalId);
        Assert.Single(own); Assert.Empty(foreign); Assert.Empty(foreignUserSales);
    }

    [Fact]
    public void Report_routes_are_wired_to_financial_read_policy()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory); string? program = null;
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName,"src","Api","Program.cs");
            if (File.Exists(candidate)) { program = candidate; break; }
            directory = directory.Parent;
        }
        Assert.NotNull(program);
        var source = File.ReadAllText(program!);
        Assert.Contains(
            "app.MapGroup(\"/api/admin/reports\").RequireAuthorization(R(BackendReadCapability.FinancialReportsRead))",
            source);
    }

    [Theory]
    [InlineData("Manager")]
    [InlineData("Administrator")]
    public async Task Financial_roles_can_read_advanced_reports(string role)
    {
        await using var test = await SqlServerTestDatabase.CreateAsync();
        var now = DateTimeOffset.UtcNow;
        var tenant = await test.SeedTenantAsync($"FIN-{role}",role:role);
        var product = await AddProductAsync(test,tenant.Business,"FIN","Financial");
        await AddSaleAsync(test,tenant,product,now,totalCents:1000,allocationCostCents:300);

        var result = await new RemoteReportService(test.Db).SummaryAsync(
            Context(tenant),
            Period(now),
            TestContext.Current.CancellationToken);

        Assert.Equal(1000,result.NetSalesCents);
        Assert.Equal(300,result.FifoCostCents);
    }
}
