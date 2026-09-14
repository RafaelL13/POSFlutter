using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBusinessBranding : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "BrandingUpdatedAt",
                table: "Businesses",
                type: "datetimeoffset",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DisplayName",
                table: "Businesses",
                type: "nvarchar(160)",
                maxLength: 160,
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "LogoBlob",
                table: "Businesses",
                type: "varbinary(max)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "LogoMimeType",
                table: "Businesses",
                type: "nvarchar(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PrimaryColor",
                table: "Businesses",
                type: "int",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BrandingUpdatedAt",
                table: "Businesses");

            migrationBuilder.DropColumn(
                name: "DisplayName",
                table: "Businesses");

            migrationBuilder.DropColumn(
                name: "LogoBlob",
                table: "Businesses");

            migrationBuilder.DropColumn(
                name: "LogoMimeType",
                table: "Businesses");

            migrationBuilder.DropColumn(
                name: "PrimaryColor",
                table: "Businesses");
        }
    }
}
