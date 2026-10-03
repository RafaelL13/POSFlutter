using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddDeviceEnrollmentMode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "RequestedMode",
                table: "DeviceEnrollmentTokens",
                type: "nvarchar(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "AdminReadOnly");

            migrationBuilder.AddCheckConstraint(
                name: "CK_DeviceEnrollmentToken_RequestedMode",
                table: "DeviceEnrollmentTokens",
                sql: "[RequestedMode] IN ('PointOfSale','AdminReadOnly')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_DeviceEnrollmentToken_RequestedMode",
                table: "DeviceEnrollmentTokens");

            migrationBuilder.DropColumn(
                name: "RequestedMode",
                table: "DeviceEnrollmentTokens");
        }
    }
}
