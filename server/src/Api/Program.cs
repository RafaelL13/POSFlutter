using System.Data;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pos.Application;
using Pos.Domain;
using Pos.Infrastructure;
using System.Threading.RateLimiting;

var builder=WebApplication.CreateBuilder(args);
var connection=builder.Configuration.GetConnectionString("SqlServer") ?? throw new InvalidOperationException("ConnectionStrings:SqlServer is required.");
builder.Services.AddDbContext<PosDbContext>(o=>o.UseSqlServer(connection));
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.Section));
var jwt=builder.Configuration.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions();
if(string.IsNullOrWhiteSpace(jwt.SigningKey)) throw new InvalidOperationException("Jwt:SigningKey is required and must be supplied by environment/User Secrets.");
builder.Services.AddScoped<TokenService>(); builder.Services.AddScoped<ITokenService>(sp=>sp.GetRequiredService<TokenService>()); builder.Services.AddScoped<ISyncService,SyncService>(); builder.Services.AddScoped<DeviceEnrollmentService>(); builder.Services.AddScoped<TenantReadService>(); builder.Services.AddScoped<RemoteReportService>();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o=>{o.TokenValidationParameters=new TokenValidationParameters{ValidateIssuer=true,ValidIssuer=jwt.Issuer,ValidateAudience=true,ValidAudience=jwt.Audience,ValidateIssuerSigningKey=true,IssuerSigningKey=new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),ValidateLifetime=true,ClockSkew=TimeSpan.FromMinutes(1)};});
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Administrator", policy => policy.RequireRole("Administrator"));
    foreach (var capability in Enum.GetValues<BackendReadCapability>())
    {
        options.AddPolicy(
            BackendReadAuthorization.PolicyName(capability),
            policy => policy.RequireAssertion(context =>
                BackendReadAuthorization.PermissionFor(
                    context.User.FindFirst(ClaimTypes.Role)?.Value,
                    context.User.FindFirst("device_mode")?.Value,
                    capability) != BackendReadPermission.None));
    }
});
builder.Services.AddRateLimiter(o=>
{
    o.AddPolicy("enrollment", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
});
builder.Services.AddHealthChecks().AddDbContextCheck<PosDbContext>(); builder.Services.AddOpenApi(); builder.Services.AddEndpointsApiExplorer(); builder.Services.AddSwaggerGen();
var app=builder.Build();
app.UseHttpsRedirection();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.Use(async (context,next) =>
{
    try
    {
        await next(context);
    }
    catch (UnauthorizedAccessException)
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        await context.Response.WriteAsJsonAsync(new
        {
            errorCode = SyncErrorCodes.AuthorizationDenied,
            message = "The authenticated context is not authorized."
        });
    }
});
if(app.Environment.IsDevelopment()){app.MapOpenApi();app.UseSwagger();app.UseSwaggerUI();}
app.MapHealthChecks("/health");

app.MapPost("/api/auth/login",async(LoginRequest r,ITokenService s,CancellationToken ct)=>(await s.LoginAsync(r,ct)) is { } a?Results.Ok(a):Results.Unauthorized());
app.MapPost("/api/auth/refresh",async(RefreshRequest r,ITokenService s,CancellationToken ct)=>(await s.RefreshAsync(r,ct)) is { } a?Results.Ok(a):Results.Unauthorized());

app.MapPost("/api/bootstrap",async(BootstrapRequest r,PosDbContext db,TokenService tokens,CancellationToken ct)=>{
 await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
 var existing=await db.Businesses.SingleOrDefaultAsync(x=>x.GlobalId==r.BusinessGlobalId,ct);
 if(existing is not null){
   var exact=await (from existingBusiness in db.Businesses where existingBusiness.GlobalId==r.BusinessGlobalId
                    join existingBranch in db.Branches on existingBusiness.Id equals existingBranch.BusinessId
                    join existingDevice in db.Devices on existingBranch.Id equals existingDevice.BranchId
                    join existingUser in db.Users on existingBusiness.Id equals existingUser.BusinessId
                    where existingBranch.GlobalId==r.BranchGlobalId && existingDevice.GlobalId==r.DeviceGlobalId && existingUser.GlobalId==r.UserGlobalId &&
                          existingUser.Username==r.Username && existingUser.PasswordHash==r.PasswordHash && existingUser.PasswordSalt==r.PasswordSalt
                    select new {b=existingBusiness,br=existingBranch,d=existingDevice,u=existingUser}).SingleOrDefaultAsync(ct);
   if(exact is null){await tx.RollbackAsync(ct);return Results.Conflict();}
   var recovered=await tokens.IssueForBootstrapAsync(exact.b.GlobalId,exact.br.GlobalId,exact.d.GlobalId,exact.u.GlobalId,ct);
   await tx.CommitAsync(ct); return recovered is null?Results.Conflict():Results.Ok(recovered);
 }
 if(await db.Businesses.AnyAsync(ct)){await tx.RollbackAsync(ct);return Results.Conflict();}
 if(r.BusinessGlobalId==Guid.Empty||r.BranchGlobalId==Guid.Empty||r.DeviceGlobalId==Guid.Empty||r.UserGlobalId==Guid.Empty||string.IsNullOrWhiteSpace(r.PasswordHash)||string.IsNullOrWhiteSpace(r.PasswordSalt)){await tx.RollbackAsync(ct);return Results.BadRequest();}
 var now=DateTimeOffset.UtcNow;
 var b=new Business{GlobalId=r.BusinessGlobalId,Name=r.BusinessName.Trim(),Active=true,CreatedAt=now,UpdatedAt=now,ServerVersion=1};db.Businesses.Add(b);await db.SaveChangesAsync(ct);
 var br=new Branch{GlobalId=r.BranchGlobalId,BusinessId=b.Id,Name=r.BranchName.Trim(),Active=true,CreatedAt=now,UpdatedAt=now,ServerVersion=1};db.Branches.Add(br);await db.SaveChangesAsync(ct);
 var d=new Device{GlobalId=r.DeviceGlobalId,BranchId=br.Id,Name=r.DeviceName.Trim(),Mode="PointOfSale",Active=true,CreatedAt=now,LastSyncAt=now,ServerVersion=1};
 var u=new UserAccount{GlobalId=r.UserGlobalId,BusinessId=b.Id,Name=r.UserDisplayName.Trim(),Username=r.Username.Trim(),PasswordHash=r.PasswordHash,PasswordSalt=r.PasswordSalt,Role="Administrator",Active=true,CreatedAt=now,UpdatedAt=now,ServerVersion=1};db.AddRange(d,u);await db.SaveChangesAsync(ct);
 var auth=await tokens.IssueForBootstrapAsync(b.GlobalId,br.GlobalId,d.GlobalId,u.GlobalId,ct); if(auth is null){await tx.RollbackAsync(ct);return Results.Conflict();}
 await tx.CommitAsync(ct);return Results.Ok(auth);
});

app.MapPost("/api/device-enrollment/invitations",async(CreateDeviceEnrollmentRequest r,HttpContext http,DeviceEnrollmentService s,CancellationToken ct)=>Results.Ok(await s.CreateInvitationAsync(TenantClaims.Require(http.User),r,ct))).RequireAuthorization("Administrator");
app.MapPost("/api/device-enrollment/redeem",async(RedeemDeviceEnrollmentRequest r,DeviceEnrollmentService s,CancellationToken ct)=>(await s.RedeemAsync(r,ct)) is { } x?Results.Ok(x):Results.BadRequest(new{message="Unable to enroll device."})).RequireRateLimiting("enrollment");
app.MapPost("/api/sync/push",async(SyncPushRequest r,HttpContext h,ISyncService s,CancellationToken ct)=>Results.Ok(await s.PushAsync(r,TenantClaims.Require(h.User),ct))).RequireAuthorization();
app.MapGet("/api/sync/pull",async(long? cursor,int? limit,HttpContext h,ISyncService s,CancellationToken ct)=>Results.Ok(await s.PullAsync(cursor??0,limit??100,TenantClaims.Require(h.User),ct))).RequireAuthorization();

static SyncTenantContext T(HttpContext h)=>TenantClaims.Require(h.User);
static string R(BackendReadCapability capability) => BackendReadAuthorization.PolicyName(capability);
app.MapGet("/api/reports/dashboard",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(await r.DashboardAsync(T(h),ct))).RequireAuthorization(R(BackendReadCapability.SalesRead));
app.MapGet("/api/products",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.ProductsAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.ProductsRead));
app.MapGet("/api/categories",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.CategoriesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.CategoriesRead));
app.MapGet("/api/suppliers",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.SuppliersAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.SuppliersRead));
app.MapGet("/api/sales",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.SalesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.SalesRead));
app.MapGet("/api/sales/{globalId:guid}",async(Guid globalId,HttpContext h,TenantReadService r,CancellationToken ct)=>(await r.SaleAsync(T(h),globalId,ct)) is { } sale?Results.Ok(sale):Results.NotFound()).RequireAuthorization(R(BackendReadCapability.SalesRead));
app.MapGet("/api/purchases",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.PurchasesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.PurchasesRead));
app.MapGet("/api/inventory",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.InventoryAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.InventoryAvailabilityRead));
app.MapGet("/api/inventory/lots",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.LotsAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.InventoryLotsRead));
app.MapGet("/api/expenses",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.ExpensesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.ExpensesRead));
app.MapGet("/api/cash/sessions",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.CashAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.CashRead));
app.MapGet("/api/cash",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.CashAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.CashRead));
app.MapGet("/api/users",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.UsersAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.UsersRead));
app.MapGet("/api/devices",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.DevicesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.DevicesRead));
app.MapGet("/api/business",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(await r.BusinessAsync(T(h),ct))).RequireAuthorization(R(BackendReadCapability.BusinessRead));
app.MapGet("/api/branches",async(HttpContext h,TenantReadService r,CancellationToken ct)=>Results.Ok(new{items=await r.BranchesAsync(T(h),ct)})).RequireAuthorization(R(BackendReadCapability.BranchesRead));

var reportApi=app.MapGroup("/api/admin/reports").RequireAuthorization(R(BackendReadCapability.FinancialReportsRead));
reportApi.MapGet("/summary",async(DateTimeOffset? from,DateTimeOffset? to,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period. Use from inclusive and to exclusive, maximum 366 days."});
 return Results.Ok(await r.SummaryAsync(T(h),period,ct));
});
reportApi.MapGet("/sales",async(DateTimeOffset? from,DateTimeOffset? to,string? groupBy,Guid? userGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 try{return Results.Ok(new{items=await r.SalesAsync(T(h),period,groupBy??"day",ct,userGlobalId)});}catch(ArgumentException ex){return Results.BadRequest(new{message=ex.Message});}
});
reportApi.MapGet("/sales/details",async(DateTimeOffset? from,DateTimeOffset? to,int? page,int? pageSize,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(await r.SaleDetailsAsync(T(h),period,page??1,pageSize??50,ct));
});
reportApi.MapGet("/products",async(DateTimeOffset? from,DateTimeOffset? to,string? sortBy,bool? descending,int? top,Guid? productGlobalId,Guid? categoryGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{items=await r.ProductsAsync(T(h),period,sortBy??"revenue",descending??true,top??20,ct,productGlobalId,categoryGlobalId)});
});
reportApi.MapGet("/products/low-performance",async(DateTimeOffset? from,DateTimeOffset? to,string? metric,int? top,Guid? productGlobalId,Guid? categoryGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{metric=metric??"revenue",definition="revenue=lowest revenue; units=lowest units; no-sales=no transactions; negative-margin=gross profit below zero",items=await r.LowPerformanceAsync(T(h),period,metric??"revenue",top??20,ct,productGlobalId,categoryGlobalId)});
});
reportApi.MapGet("/categories",async(DateTimeOffset? from,DateTimeOffset? to,Guid? categoryGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{items=await r.CategoriesAsync(T(h),period,ct,categoryGlobalId)});
});
reportApi.MapGet("/users",async(DateTimeOffset? from,DateTimeOffset? to,Guid? userGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{items=await r.UsersAsync(T(h),period,ct,userGlobalId)});
});
reportApi.MapGet("/purchases",async(DateTimeOffset? from,DateTimeOffset? to,string? groupBy,Guid? supplierGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 try{return Results.Ok(new{items=await r.PurchasesAsync(T(h),period,groupBy??"supplier",ct,supplierGlobalId)});}catch(ArgumentException ex){return Results.BadRequest(new{message=ex.Message});}
});
reportApi.MapGet("/suppliers",async(DateTimeOffset? from,DateTimeOffset? to,Guid? supplierGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{items=await r.SuppliersAsync(T(h),period,ct,supplierGlobalId)});
});
reportApi.MapGet("/inventory",async(Guid? productGlobalId,Guid? categoryGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>Results.Ok(new{items=await r.InventoryAsync(T(h),ct,productGlobalId,categoryGlobalId)}));
reportApi.MapGet("/expenses",async(DateTimeOffset? from,DateTimeOffset? to,string? groupBy,int? page,int? pageSize,Guid? userGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 try{return Results.Ok(await r.ExpensesAsync(T(h),period,groupBy??"category",page??1,pageSize??50,ct,userGlobalId));}catch(ArgumentException ex){return Results.BadRequest(new{message=ex.Message});}
});
reportApi.MapGet("/cash",async(DateTimeOffset? from,DateTimeOffset? to,int? page,int? pageSize,Guid? userGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(await r.CashAsync(T(h),period,page??1,pageSize??50,ct,userGlobalId));
});
reportApi.MapGet("/payment-methods",async(DateTimeOffset? from,DateTimeOffset? to,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{items=await r.PaymentMethodsAsync(T(h),period,ct)});
});
reportApi.MapGet("/cancellations",async(DateTimeOffset? from,DateTimeOffset? to,int? page,int? pageSize,Guid? userGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(await r.CancellationsAsync(T(h),period,page??1,pageSize??50,ct,userGlobalId));
});
reportApi.MapGet("/trends/products",async(DateTimeOffset? from,DateTimeOffset? to,int? top,Guid? productGlobalId,Guid? categoryGlobalId,HttpContext h,RemoteReportService r,CancellationToken ct)=>
{
 if(!TryReportPeriod(from,to,out var period))return Results.BadRequest(new{message="Invalid report period."});
 return Results.Ok(new{stableThresholdPercent=5.0,comparison="current period versus immediately preceding equal-length period",items=await r.ProductTrendsAsync(T(h),period,top??50,ct,productGlobalId,categoryGlobalId)});
});

app.Run();

static bool TryReportPeriod(DateTimeOffset? from,DateTimeOffset? to,out ReportPeriod period)
{
 var end=(to??DateTimeOffset.UtcNow).ToUniversalTime();
 var start=(from??new DateTimeOffset(end.UtcDateTime.Date,TimeSpan.Zero)).ToUniversalTime();
 var span=end-start;
 if(span<=TimeSpan.Zero||span>TimeSpan.FromDays(366)){period=new ReportPeriod(start,end);return false;}
 period=new ReportPeriod(start,end);return true;
}

public partial class Program { }
