using System.Security.Cryptography;
using System.Text;

namespace Pos.Infrastructure;

public static class PasswordHashing
{
    private const int Iterations = 210_000;
    public static (string Hash,string Salt) Create(string password)
    {
        var salt=RandomNumberGenerator.GetBytes(16);
        var hash=Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password),salt,Iterations,HashAlgorithmName.SHA256,32);
        return (Convert.ToBase64String(hash),Convert.ToBase64String(salt));
    }
    public static bool Verify(string password,string encodedHash,string encodedSalt)
    {
        try
        {
            var salt=Convert.FromBase64String(encodedSalt);
            var expected=Convert.FromBase64String(encodedHash);
            var actual=Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password),salt,Iterations,HashAlgorithmName.SHA256,expected.Length);
            return CryptographicOperations.FixedTimeEquals(actual,expected);
        }
        catch(FormatException){return false;}
    }
}
