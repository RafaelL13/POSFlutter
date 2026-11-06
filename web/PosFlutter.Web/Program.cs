using PosFlutter.Web.Services;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Pos.Infrastructure;
using System.Threading.RateLimiting;
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews(o => o.Filters.Add(new Microsoft.AspNetCore.Mvc.AutoValidateAntiforgeryTokenAttribute()));
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(o => { o.Cookie.Name = "__Host-PosWeb"; o.Cookie.HttpOnly=true; o.Cookie.SecurePolicy=CookieSecurePolicy.Always; o.Cookie.SameSite=SameSiteMode.Lax; o.Cookie.IsEssential=true; o.IdleTimeout=TimeSpan.FromMinutes(30); });
var sqlConnection=builder.Configuration.GetConnectionString("SqlServer") ?? throw new InvalidOperationException("ConnectionStrings:SqlServer is required.");
builder.Services.AddDbContext<PosDbContext>(o=>o.UseSqlServer(sqlConnection));
builder.Services.AddScoped<TenantReadService>();
builder.Services.AddScoped<RemoteReportService>();
builder.Services.AddScoped<WebCheckoutService>();
builder.Services.AddScoped<WebSaleCancellationService>();
builder.Services.AddScoped<PurchaseReceivingService>();
builder.Services.AddScoped<WebTenantSession>();
builder.Services.AddRateLimiter(options => {
 options.RejectionStatusCode=StatusCodes.Status429TooManyRequests;
 options.AddPolicy("web-login", http => RateLimitPartition.GetFixedWindowLimiter(
  http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
  _ => new FixedWindowRateLimiterOptions {
   PermitLimit=8, Window=TimeSpan.FromMinutes(1), AutoReplenishment=true, QueueLimit=0
  }));
});
builder.Services.AddAntiforgery(o=>o.HeaderName="X-CSRF-TOKEN");
builder.Services.Configure<ForwardedHeadersOptions>(o=> {o.ForwardedHeaders=ForwardedHeaders.XForwardedFor|ForwardedHeaders.XForwardedProto;});
var app=builder.Build();
if(!app.Environment.IsDevelopment()) { app.UseExceptionHandler("/Home/Error"); app.UseHsts(); }
app.UseHttpsRedirection(); app.UseStaticFiles(); app.UseRouting();
app.Use(async (ctx,next)=> { ctx.Response.Headers["X-Content-Type-Options"]="nosniff";ctx.Response.Headers["Referrer-Policy"]="no-referrer";ctx.Response.Headers["X-Frame-Options"]="DENY";ctx.Response.Headers["Content-Security-Policy"]="default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";ctx.Response.Headers["Cache-Control"]="no-store";await next(); });
app.UseSession(); app.UseRateLimiter();
app.MapGet("/health",async (PosDbContext db,CancellationToken ct) =>
    await db.Database.CanConnectAsync(ct) ? Results.Ok(new { status="healthy",sqlServer=true }) : Results.StatusCode(StatusCodes.Status503ServiceUnavailable));
app.MapControllerRoute(name:"default",pattern:"{controller=Home}/{action=Index}/{id?}");
app.Run();
public partial class Program { }
