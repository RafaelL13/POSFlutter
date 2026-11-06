using System.IO.Compression;
using System.Text;
using Pos.Application;
using PosFlutter.Web.Services;

namespace Pos.Infrastructure.Tests;

public sealed class ReportExportWriterTests
{
    private static readonly ReportPeriod Period=new(new DateTimeOffset(2026,10,1,0,0,0,TimeSpan.Zero),new DateTimeOffset(2026,11,1,0,0,0,TimeSpan.Zero));
    private static readonly IReadOnlyList<SaleReportDetailRow> Rows=[new(Guid.NewGuid(),"=FORMULA",new DateTimeOffset(2026,10,2,12,0,0,TimeSpan.Zero),"Ana","Card","Confirmed",2,1250,500,750)];
    [Fact] public void Csv_has_headers_data_and_formula_neutralization()
    { var csv=Encoding.UTF8.GetString(ReportExportWriter.Write("csv",Rows,Period)); Assert.Contains("\"Folio\",\"Fecha\"",csv); Assert.Contains("'=FORMULA",csv); Assert.Contains("12.50",csv); }
    [Fact] public void Xlsx_is_a_valid_openxml_package_with_sales_sheet_and_values()
    { using var zip=new ZipArchive(new MemoryStream(ReportExportWriter.Write("xlsx",Rows,Period)),ZipArchiveMode.Read); Assert.NotNull(zip.GetEntry("xl/workbook.xml")); var sheet=zip.GetEntry("xl/worksheets/sheet1.xml"); Assert.NotNull(sheet); using var reader=new StreamReader(sheet!.Open()); var xml=reader.ReadToEnd(); Assert.Contains("Ventas",zip.GetEntry("xl/workbook.xml")!.OpenText()); Assert.Contains("=FORMULA",xml); Assert.Contains("12.50",xml); }
    [Fact] public void Pdf_has_valid_signature_and_expected_content()
    { var pdf=Encoding.ASCII.GetString(ReportExportWriter.Write("pdf",Rows,Period)); Assert.StartsWith("%PDF-1.4",pdf); Assert.Contains("Reporte de ventas autorizado",pdf); Assert.Contains("FORMULA",pdf); Assert.Contains("%%EOF",pdf); }
}

file static class StreamReaderExtensions { public static string OpenText(this ZipArchiveEntry entry) { using var r=new StreamReader(entry.Open()); return r.ReadToEnd(); } }
