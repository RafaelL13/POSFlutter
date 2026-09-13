using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSalePayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SalePayments",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    GlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SaleId = table.Column<long>(type: "bigint", nullable: false),
                    Method = table.Column<string>(type: "nvarchar(16)", maxLength: 16, nullable: false),
                    AmountCents = table.Column<long>(type: "bigint", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalePayments", x => x.Id);
                    table.CheckConstraint("CK_SalePayment_Amount", "[AmountCents] > 0");
                    table.CheckConstraint("CK_SalePayment_Method", "[Method] IN ('Cash','Card','Transfer')");
                    table.ForeignKey(
                        name: "FK_SalePayments_Sales_SaleId",
                        column: x => x.SaleId,
                        principalTable: "Sales",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.Sql(
                """
                IF EXISTS (
                    SELECT 1
                    FROM Sales
                    WHERE TotalCents <= 0
                       OR PaymentMethod NOT IN ('Cash','Card','Transfer')
                )
                    THROW 51000, 'Legacy sales contain values that cannot be migrated to SalePayments.', 1;

                INSERT INTO SalePayments (GlobalId, SaleId, Method, AmountCents, CreatedAt)
                SELECT GlobalId, Id, PaymentMethod, TotalCents, CreatedAt
                FROM Sales;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_SalePayments_GlobalId",
                table: "SalePayments",
                column: "GlobalId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SalePayments_SaleId_Method",
                table: "SalePayments",
                columns: new[] { "SaleId", "Method" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SalePayments");
        }
    }
}
