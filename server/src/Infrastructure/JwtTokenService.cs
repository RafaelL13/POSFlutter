using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Pos.Application;
using Pos.Domain;

namespace Pos.Infrastructure;

public sealed class JwtOptions
{
    public const string Section="Jwt";
    public string Issuer {get;set;}="POSFlutter";
    public string Audience {get;set;}="POSFlutter.Client";
    public string SigningKey {get;set;}="";
    public int AccessMinutes {get;set;}=30;
    public int RefreshDays {get;set;}=30;
}

public sealed class TokenService(PosDbContext db,IOptions<JwtOptions> options) : ITokenService
{
    private readonly PosDbContext _db=db;
    private readonly JwtOptions _options=options.Value;

    public async Task<AuthResponse?> LoginAsync(LoginRequest request,CancellationToken ct)
    {
        var row=await (from b in _db.Businesses.AsNoTracking()
                       join br in _db.Branches.AsNoTracking() on b.Id equals br.BusinessId
                       join d in _db.Devices.AsNoTracking() on br.Id equals d.BranchId
                       join u in _db.Users.AsNoTracking() on b.Id equals u.BusinessId
                       where b.GlobalId==request.BusinessGlobalId && b.Active && d.GlobalId==request.DeviceGlobalId && d.Active && br.Active && u.Username==request.Username && u.Active
                       select new {b,br,d,u}).SingleOrDefaultAsync(ct);
        if(row is null || !PasswordHashing.Verify(request.Password,row.u.PasswordHash,row.u.PasswordSalt)) return null;
        return await IssueAsync(row.b,row.br,row.d,row.u,ct);
    }

    public async Task<AuthResponse?> RefreshAsync(RefreshRequest request,CancellationToken ct)
    {
        var hash=Hash(request.RefreshToken);var now=DateTimeOffset.UtcNow;
        var stored=await _db.RefreshTokens.SingleOrDefaultAsync(x=>x.TokenHash==hash && x.RevokedAt==null && x.ExpiresAt>now,ct);
        if(stored is null)return null;
        var row=await (from b in _db.Businesses.AsNoTracking()
                       join br in _db.Branches.AsNoTracking() on b.Id equals br.BusinessId
                       join d in _db.Devices.AsNoTracking() on br.Id equals d.BranchId
                       join u in _db.Users.AsNoTracking() on b.Id equals u.BusinessId
                       where b.Id==stored.BusinessId && d.Id==stored.DeviceId && u.Id==stored.UserId && b.Active && br.Active && d.Active && u.Active
                       select new {b,br,d,u}).SingleOrDefaultAsync(ct);
        if(row is null)return null;stored.RevokedAt=now;return await IssueAsync(row.b,row.br,row.d,row.u,ct);
    }

    public async Task<AuthResponse?> IssueForBootstrapAsync(Guid businessGid,Guid branchGid,Guid deviceGid,Guid userGid,CancellationToken ct)
    {
        var row=await (from b in _db.Businesses.AsNoTracking()
                       join br in _db.Branches.AsNoTracking() on b.Id equals br.BusinessId
                       join d in _db.Devices.AsNoTracking() on br.Id equals d.BranchId
                       join u in _db.Users.AsNoTracking() on b.Id equals u.BusinessId
                       where b.GlobalId==businessGid && br.GlobalId==branchGid && d.GlobalId==deviceGid && u.GlobalId==userGid
                       select new {b,br,d,u}).SingleOrDefaultAsync(ct);
        return row is null?null:await IssueAsync(row.b,row.br,row.d,row.u,ct);
    }

    private async Task<AuthResponse> IssueAsync(Business business,Branch branch,Device device,UserAccount user,CancellationToken ct)
    {
        var now=DateTimeOffset.UtcNow;var accessExpires=now.AddMinutes(Math.Clamp(_options.AccessMinutes,5,120));
        var claims=new[]{new Claim(ClaimTypes.NameIdentifier,user.Id.ToString()),new Claim(ClaimTypes.Name,user.Username),new Claim(ClaimTypes.Role,user.Role),new Claim("business_id",business.Id.ToString()),new Claim("business_gid",business.GlobalId.ToString()),new Claim("branch_id",branch.Id.ToString()),new Claim("branch_gid",branch.GlobalId.ToString()),new Claim("device_id",device.Id.ToString()),new Claim("device_gid",device.GlobalId.ToString()),new Claim("device_mode",device.Mode),new Claim("user_gid",user.GlobalId.ToString())};
        var key=new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey));
        var jwt=new JwtSecurityToken(_options.Issuer,_options.Audience,claims,now.UtcDateTime,accessExpires.UtcDateTime,new SigningCredentials(key,SecurityAlgorithms.HmacSha256));
        var access=new JwtSecurityTokenHandler().WriteToken(jwt);var refresh=Base64Url(RandomNumberGenerator.GetBytes(48));
        _db.RefreshTokens.Add(new RefreshToken{BusinessId=business.Id,UserId=user.Id,DeviceId=device.Id,TokenHash=Hash(refresh),CreatedAt=now,ExpiresAt=now.AddDays(Math.Clamp(_options.RefreshDays,1,90))});await _db.SaveChangesAsync(ct);
        return new AuthResponse(access,refresh,accessExpires,business.GlobalId,branch.GlobalId,device.GlobalId,device.Mode,user.GlobalId,user.Role);
    }
    private static string Hash(string value)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    private static string Base64Url(byte[] b)=>Convert.ToBase64String(b).TrimEnd('=').Replace('+','-').Replace('/','_');
}
