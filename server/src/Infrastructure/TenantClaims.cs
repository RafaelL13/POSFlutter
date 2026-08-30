using System.Security.Claims;
using Pos.Application;

namespace Pos.Infrastructure;
public static class TenantClaims
{
    public static SyncTenantContext Require(ClaimsPrincipal user)
    {
        static string Claim(ClaimsPrincipal principal, string type) =>
            principal.FindFirst(type)?.Value ??
            throw new UnauthorizedAccessException("Missing tenant claim.");

        static long LongClaim(ClaimsPrincipal principal, string type) =>
            long.TryParse(Claim(principal, type), out var value)
                ? value
                : throw new UnauthorizedAccessException("Invalid tenant claim.");

        static Guid GuidClaim(ClaimsPrincipal principal, string type) =>
            Guid.TryParse(Claim(principal, type), out var value) && value != Guid.Empty
                ? value
                : throw new UnauthorizedAccessException("Invalid tenant claim.");

        return new SyncTenantContext(
            LongClaim(user, "business_id"),
            GuidClaim(user, "business_gid"),
            LongClaim(user, "branch_id"),
            GuidClaim(user, "branch_gid"),
            LongClaim(user, "device_id"),
            GuidClaim(user, "device_gid"),
            LongClaim(user, ClaimTypes.NameIdentifier),
            GuidClaim(user, "user_gid"),
            Claim(user, ClaimTypes.Role),
            Claim(user, "device_mode"));
    }
}
