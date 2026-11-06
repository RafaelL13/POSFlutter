using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Pos.Infrastructure;

#nullable disable

namespace Infrastructure.Migrations;

/// <summary>
/// Reserved migration identifier. The commercial model was clarified before this
/// migration was applied: combo components and stock are pieces, while package
/// content belongs to Product.Presentation. It intentionally makes no schema
/// change and preserves the migration chain without touching existing databases.
/// </summary>
[DbContext(typeof(PosDbContext))]
[Migration("20261102190000_AddAdminComboDecimalQuantity")]
public partial class AddAdminComboDecimalQuantity : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Intentionally empty; see class documentation.
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Intentionally empty; Up made no schema change.
    }
}
