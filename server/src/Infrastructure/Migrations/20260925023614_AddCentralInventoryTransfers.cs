using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddCentralInventoryTransfers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "CentralInventoryTransferReceipts",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TransferGlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    BusinessId = table.Column<long>(type: "bigint", nullable: false),
                    BranchId = table.Column<long>(type: "bigint", nullable: false),
                    ReceivedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CentralInventoryTransferReceipts", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CentralInventoryTransferReceipts_BusinessId_BranchId_ReceivedAt",
                table: "CentralInventoryTransferReceipts",
                columns: new[] { "BusinessId", "BranchId", "ReceivedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_CentralInventoryTransferReceipts_BusinessId_TransferGlobalId",
                table: "CentralInventoryTransferReceipts",
                columns: new[] { "BusinessId", "TransferGlobalId" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "CentralInventoryTransferReceipts");
        }
    }
}
