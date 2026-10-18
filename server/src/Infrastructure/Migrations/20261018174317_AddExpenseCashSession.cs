using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddExpenseCashSession : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "CashSessionId",
                table: "Expenses",
                type: "bigint",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Expenses_CashSessionId",
                table: "Expenses",
                column: "CashSessionId");

            migrationBuilder.AddForeignKey(
                name: "FK_Expenses_CashSessions_CashSessionId",
                table: "Expenses",
                column: "CashSessionId",
                principalTable: "CashSessions",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Expenses_CashSessions_CashSessionId",
                table: "Expenses");

            migrationBuilder.DropIndex(
                name: "IX_Expenses_CashSessionId",
                table: "Expenses");

            migrationBuilder.DropColumn(
                name: "CashSessionId",
                table: "Expenses");
        }
    }
}
