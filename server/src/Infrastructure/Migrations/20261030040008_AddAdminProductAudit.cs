using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminProductAudit : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Some early LAB packages created this append-only table before the
            // migration was recorded.  Keep this additive migration safe for both
            // those LABs and clean SQL Server databases.
            migrationBuilder.Sql(@"
IF OBJECT_ID(N'[dbo].[AdminProductAudits]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[AdminProductAudits] (
        [Id] bigint IDENTITY(1,1) NOT NULL,
        [BusinessId] bigint NOT NULL, [BranchId] bigint NOT NULL,
        [ActorUserId] bigint NOT NULL, [ActorUserGlobalId] uniqueidentifier NOT NULL,
        [ActorDeviceId] bigint NOT NULL, [ProductGlobalId] uniqueidentifier NOT NULL,
        [Operation] nvarchar(12) NOT NULL, [PreviousServerVersion] bigint NULL,
        [NewServerVersion] bigint NOT NULL, [SyncChangeId] bigint NOT NULL,
        [BeforeJson] nvarchar(max) NULL, [AfterJson] nvarchar(max) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_AdminProductAudits] PRIMARY KEY ([Id]),
        CONSTRAINT [CK_AdminProductAudit_Operation] CHECK ([Operation] IN ('Create','Update')),
        CONSTRAINT [CK_AdminProductAudit_Versions] CHECK (([Operation] = 'Create' AND [PreviousServerVersion] IS NULL AND [NewServerVersion] = 1) OR ([Operation] = 'Update' AND [PreviousServerVersion] >= 1 AND [NewServerVersion] = [PreviousServerVersion] + 1))
    );
END;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[AdminProductAudits]') AND name = N'IX_AdminProductAudits_BusinessId_ProductGlobalId_CreatedAt')
    CREATE INDEX [IX_AdminProductAudits_BusinessId_ProductGlobalId_CreatedAt] ON [dbo].[AdminProductAudits] ([BusinessId], [ProductGlobalId], [CreatedAt]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[AdminProductAudits]') AND name = N'IX_AdminProductAudits_BusinessId_SyncChangeId')
    CREATE UNIQUE INDEX [IX_AdminProductAudits_BusinessId_SyncChangeId] ON [dbo].[AdminProductAudits] ([BusinessId], [SyncChangeId]);
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AdminProductAudits");
        }
    }
}
