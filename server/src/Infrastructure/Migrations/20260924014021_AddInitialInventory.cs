using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddInitialInventory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "InitialInventories",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    GlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    BusinessId = table.Column<long>(type: "bigint", nullable: false),
                    BranchId = table.Column<long>(type: "bigint", nullable: false),
                    DeviceId = table.Column<long>(type: "bigint", nullable: false),
                    UserId = table.Column<long>(type: "bigint", nullable: false),
                    SourceFingerprint = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    SourceName = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    ValidRows = table.Column<int>(type: "int", nullable: false),
                    TotalUnits = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_InitialInventories", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "InitialInventoryLines",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    GlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    InitialInventoryId = table.Column<long>(type: "bigint", nullable: false),
                    ProductGlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    InventoryLotGlobalId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Quantity = table.Column<int>(type: "int", nullable: false),
                    UnitCostCents = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_InitialInventoryLines", x => x.Id);
                    table.CheckConstraint("CK_InitialInventoryLine_Quantity", "[Quantity] > 0");
                    table.ForeignKey(
                        name: "FK_InitialInventoryLines_InitialInventories_InitialInventoryId",
                        column: x => x.InitialInventoryId,
                        principalTable: "InitialInventories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_InitialInventories_BusinessId_BranchId_SourceFingerprint",
                table: "InitialInventories",
                columns: new[] { "BusinessId", "BranchId", "SourceFingerprint" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_InitialInventories_BusinessId_GlobalId",
                table: "InitialInventories",
                columns: new[] { "BusinessId", "GlobalId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_InitialInventoryLines_GlobalId",
                table: "InitialInventoryLines",
                column: "GlobalId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_InitialInventoryLines_InitialInventoryId_ProductGlobalId",
                table: "InitialInventoryLines",
                columns: new[] { "InitialInventoryId", "ProductGlobalId" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "InitialInventoryLines");

            migrationBuilder.DropTable(
                name: "InitialInventories");
        }
    }
}
