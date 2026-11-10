using System.ComponentModel.DataAnnotations;
namespace PosFlutter.Web.Models;
public sealed class QuoteRequest {
 [Required, MinLength(1), MaxLength(100)] public List<QuoteLine> Lines {get;set;} = new();
}
public sealed class QuoteLine {
 [Required] public Guid ProductGlobalId {get;set;}
 [Range(1,100000)] public int Quantity {get;set;}
}
