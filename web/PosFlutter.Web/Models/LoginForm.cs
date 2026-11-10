using System.ComponentModel.DataAnnotations;
namespace PosFlutter.Web.Models;
public sealed class LoginForm {
 [Required] public Guid BusinessGlobalId {get;set;}
 [Required] public Guid DeviceGlobalId {get;set;}
 [Required, MaxLength(100)] public string Username {get;set;}="";
 [Required, DataType(DataType.Password)] public string Password {get;set;}="";
}
