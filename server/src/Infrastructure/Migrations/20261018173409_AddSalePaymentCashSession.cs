using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSalePaymentCashSession : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "CashSessionId",
                table: "SalePayments",
                type: "bigint",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_SalePayments_CashSessionId",
                table: "SalePayments",
                column: "CashSessionId");

            migrationBuilder.AddForeignKey(
                name: "FK_SalePayments_CashSessions_CashSessionId",
                table: "SalePayments",
                column: "CashSessionId",
                principalTable: "CashSessions",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_SalePayments_CashSessions_CashSessionId",
                table: "SalePayments");

            migrationBuilder.DropIndex(
                name: "IX_SalePayments_CashSessionId",
                table: "SalePayments");

            migrationBuilder.DropColumn(
                name: "CashSessionId",
                table: "SalePayments");
        }
    }
}
