using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Pos.Application;
using Pos.Infrastructure;

namespace Pos.Api;
public static class WebCheckoutEndpoint
{
    public static IServiceCollection AddWebCheckout(this IServiceCollection services)
    {
        services.AddScoped<WebCheckoutService>();
        return services;
    }
    public static IEndpointRouteBuilder MapWebCheckout(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/web/checkout", async (WebCheckoutRequest body, HttpContext http,
            WebCheckoutService checkout, CancellationToken ct) =>
        {
            try
            {
                return Results.Ok(await checkout.CheckoutAsync(body, TenantClaims.Require(http.User), ct));
            }
            catch (UnauthorizedAccessException) { return Results.Forbid(); }
            catch (ArgumentException) { return Results.BadRequest(new { message = "Invalid checkout." }); }
            catch (InvalidOperationException) { return Results.Conflict(new { message = "Checkout conflict or stock unavailable." }); }
        }).RequireAuthorization();
        return app;
    }
}
