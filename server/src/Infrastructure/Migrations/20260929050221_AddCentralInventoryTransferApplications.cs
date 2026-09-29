using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddCentralInventoryTransferApplications : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "CentralInventoryTransferApplications",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    GlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TransferGlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    BusinessId = table.Column<long>(type: "bigint", nullable: false),
                    BranchId = table.Column<long>(type: "bigint", nullable: false),
                    DeviceId = table.Column<long>(type: "bigint", nullable: false),
                    AppliedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    AcknowledgedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CentralInventoryTransferApplications", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CentralInventoryTransferApplications_BusinessId_BranchId_AcknowledgedAt",
                table: "CentralInventoryTransferApplications",
                columns: new[] { "BusinessId", "BranchId", "AcknowledgedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_CentralInventoryTransferApplications_BusinessId_TransferGlobalId_DeviceId",
                table: "CentralInventoryTransferApplications",
                columns: new[] { "BusinessId", "TransferGlobalId", "DeviceId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_CentralInventoryTransferApplications_GlobalId",
                table: "CentralInventoryTransferApplications",
                column: "GlobalId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "CentralInventoryTransferApplications");
        }
    }
}
