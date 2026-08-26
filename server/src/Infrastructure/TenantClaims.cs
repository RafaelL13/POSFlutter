using System.Security.Claims;
using Pos.Application;

namespace Pos.Infrastructure;
public static class TenantClaims
{
    public static SyncTenantContext Require(ClaimsPrincipal user)
    {
        static string C(ClaimsPrincipal u,string type)=>u.FindFirstValue(type)??throw new UnauthorizedAccessException("Missing tenant claim.");
        return new SyncTenantContext(long.Parse(C(user,"business_id")),Guid.Parse(C(user,"business_gid")),long.Parse(C(user,"branch_id")),Guid.Parse(C(user,"branch_gid")),long.Parse(C(user,"device_id")),Guid.Parse(C(user,"device_gid")),long.Parse(C(user,ClaimTypes.NameIdentifier)),Guid.Parse(C(user,"user_gid")),C(user,ClaimTypes.Role),C(user,"device_mode"));
    }
}
