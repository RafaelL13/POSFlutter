using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddInventoryAdjustmentIdempotencyIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_InventoryMovements_BusinessId_BranchId_ReferenceGlobalId",
                table: "InventoryMovements",
                columns: new[] { "BusinessId", "BranchId", "ReferenceGlobalId" },
                unique: true,
                filter: "[Type] IN ('AdjustmentIn','AdjustmentOut')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_InventoryMovements_BusinessId_BranchId_ReferenceGlobalId",
                table: "InventoryMovements");
        }
    }
}
