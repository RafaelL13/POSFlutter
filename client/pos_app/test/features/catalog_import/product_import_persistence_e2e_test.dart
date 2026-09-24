import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';
import 'package:pos_app/features/catalog_import/data/initial_inventory_repository.dart';
import 'package:pos_app/features/payments/domain/sale_payment.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('P002 import and sale survive full SQLite close and reopen', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'posflutter-p002-',
    );
    final databasePath = '${tempDirectory.path}/p002.db';

    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final firstDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    final firstDb = await firstDatabase.open();
    final now = DateTime.utc(2026, 9, 24).toIso8601String();

    final businessId = await firstDb.insert('businesses', {
      'global_id': 'business-p002',
      'name': 'P002 Business',
      'created_at': now,
      'updated_at': now,
    });

    final branchId = await firstDb.insert('branches', {
      'global_id': 'branch-p002',
      'business_id': businessId,
      'name': 'Main',
      'created_at': now,
      'updated_at': now,
    });

    await firstDb.insert('devices', {
      'global_id': 'device-p002',
      'branch_id': branchId,
      'name': 'POS',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });

    await firstDb.insert('users', {
      'global_id': 'user-p002',
      'business_id': businessId,
      'name': 'Administrator',
      'username': 'admin-p002',
      'password_hash': 'h',
      'password_salt': 's',
      'role': 'Administrator',
      'created_at': now,
      'updated_at': now,
    });

    for (final entry in {
      'local_device_global_id': 'device-p002',
      'active_user_global_id': 'user-p002',
    }.entries) {
      await firstDb.insert('app_settings', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }

    final sourceBytes = utf8.encode(
      'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
      'P001,Producto P001,General,Proveedor P001,100.00,140.00,10\n',
    );

    final preview = CatalogImportCsv.parse(sourceBytes);

    expect(preview.isValid, isTrue);
    expect(preview.rows, hasLength(1));
    expect(preview.rows.single.costCents, 10000);
    expect(preview.rows.single.priceCents, 14000);
    expect(preview.rows.single.quantity, 10);

    final importGlobalId = await InitialInventoryRepository(firstDatabase)
        .import(
          preview: preview,
          policy: ExistingCatalogPolicy.skip,
          sourceName: 'P001.csv',
        );

    final product = (await firstDb.query(
      'products',
      where: 'business_id=? AND code=?',
      whereArgs: [businessId, 'P001'],
    )).single;

    final productId = product['id'] as int;
    final productGlobalId = product['global_id'] as String;

    final sale = await PosRepository(firstDatabase).completeSale(
      [
        CartLine(
          productId: productId,
          productGlobalId: productGlobalId,
          name: 'Producto P001',
          quantity: 3,
          unitPriceCents: 14000,
        ),
      ],
      payments: const [
        SalePaymentInput(method: PaymentMethod.card, amountCents: 42000),
      ],
    );

    expect(sale.totalCents, 42000);
    expect(sale.fifoCostCents, 30000);

    await firstDatabase.close();

    expect(await File(databasePath).exists(), isTrue);

    // New AppDatabase instance: no in-memory repository/database state survives.
    final reopenedDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    addTearDown(reopenedDatabase.close);

    final reopenedDb = await reopenedDatabase.open();

    final reopenedProduct = (await reopenedDb.query(
      'products',
      where: 'global_id=?',
      whereArgs: [productGlobalId],
    )).single;

    expect(reopenedProduct['code'], 'P001');
    expect(reopenedProduct['sale_price_cents'], 14000);

    final reopenedLot = (await reopenedDb.query(
      'inventory_lots',
      where: 'product_id=? AND branch_id=?',
      whereArgs: [productId, branchId],
    )).single;

    expect(reopenedLot['initial_quantity'], 10);
    expect(reopenedLot['available_quantity'], 7);
    expect(reopenedLot['unit_cost_cents'], 10000);

    final reopenedImport = (await reopenedDb.query(
      'initial_inventory_imports',
      where: 'global_id=?',
      whereArgs: [importGlobalId],
    )).single;

    expect(reopenedImport['business_id'], businessId);
    expect(reopenedImport['branch_id'], branchId);
    expect(reopenedImport['source_fingerprint'], preview.fingerprint);
    expect(reopenedImport['valid_rows'], 1);
    expect(reopenedImport['total_units'], 10);

    final importLines = await reopenedDb.query(
      'initial_inventory_lines',
      where: 'import_id=?',
      whereArgs: [reopenedImport['id']],
    );

    expect(importLines, hasLength(1));
    expect(importLines.single['product_id'], productId);
    expect(importLines.single['quantity'], 10);
    expect(importLines.single['unit_cost_cents'], 10000);

    final reopenedSale = (await reopenedDb.query(
      'sales',
      where: 'global_id=?',
      whereArgs: [sale.globalId],
    )).single;

    expect(reopenedSale['status'], 'Confirmed');
    expect(reopenedSale['subtotal_cents'], 42000);
    expect(reopenedSale['total_cents'], 42000);
    expect(reopenedSale['fifo_cost_cents'], 30000);
    expect(reopenedSale['gross_profit_cents'], 12000);

    final saleDetails = await reopenedDb.query(
      'sale_details',
      where: 'sale_id=?',
      whereArgs: [reopenedSale['id']],
    );

    expect(saleDetails, hasLength(1));

    final detail = saleDetails.single;
    expect(detail['product_id'], productId);
    expect(detail['quantity'], 3);
    expect(detail['unit_price_cents'], 14000);
    expect(detail['total_cents'], 42000);
    expect(detail['fifo_cost_cents'], 30000);

    final allocations = await reopenedDb.query(
      'sale_detail_lots',
      where: 'sale_detail_id=?',
      whereArgs: [detail['id']],
    );

    expect(allocations, hasLength(1));
    expect(allocations.single['inventory_lot_id'], reopenedLot['id']);
    expect(allocations.single['quantity'], 3);
    expect(allocations.single['unit_cost_cents'], 10000);
    expect(allocations.single['total_cost_cents'], 30000);

    final movements = await reopenedDb.query(
      'inventory_movements',
      where: 'product_id=? AND branch_id=?',
      whereArgs: [productId, branchId],
      orderBy: 'id',
    );

    expect(movements, hasLength(2));

    expect(movements.first['type'], 'InitialInventory');
    expect(movements.first['quantity_delta'], 10);
    expect(movements.first['previous_stock'], 0);
    expect(movements.first['new_stock'], 10);

    expect(movements.last['type'], 'Sale');
    expect(movements.last['quantity_delta'], -3);
    expect(movements.last['previous_stock'], 10);
    expect(movements.last['new_stock'], 7);
    expect(movements.last['reference_global_id'], sale.globalId);

    final payments = await reopenedDb.query(
      'sale_payments',
      where: 'sale_id=?',
      whereArgs: [reopenedSale['id']],
    );

    expect(payments, hasLength(1));
    expect(payments.single['method'], PaymentMethod.card.storageValue);
    expect(payments.single['amount_cents'], 42000);

    final importQueue = await reopenedDb.query(
      'sync_queue',
      where: "entity_type='InitialInventory' AND entity_global_id=?",
      whereArgs: [importGlobalId],
    );

    expect(importQueue, hasLength(1));

    final saleQueue = await reopenedDb.query(
      'sync_queue',
      where: "entity_type='Sale' AND entity_global_id=?",
      whereArgs: [sale.globalId],
    );

    expect(saleQueue, hasLength(1));
    expect(saleQueue.single['payload_version'], 2);

    final salePayload = jsonDecode(
      saleQueue.single['payload_json'] as String,
    ) as Map<String, dynamic>;

    expect(salePayload['totalCents'], 42000);
    expect(salePayload['fifoCostCents'], 30000);
    expect(salePayload['grossProfitCents'], 12000);

    // Re-import after a real close/reopen must remain idempotent.
    final reimportGlobalId = await InitialInventoryRepository(reopenedDatabase)
        .import(
          preview: preview,
          policy: ExistingCatalogPolicy.skip,
          sourceName: 'P001-after-reopen.csv',
        );

    expect(reimportGlobalId, importGlobalId);

    final importCount =
        (await reopenedDb.rawQuery(
              'SELECT COUNT(*) AS count '
              'FROM initial_inventory_imports '
              'WHERE business_id=? AND branch_id=? AND source_fingerprint=?',
              [businessId, branchId, preview.fingerprint],
            )).single['count']
            as int;

    expect(importCount, 1);

    final lotCount =
        (await reopenedDb.rawQuery(
              'SELECT COUNT(*) AS count '
              'FROM inventory_lots '
              'WHERE product_id=? AND branch_id=?',
              [productId, branchId],
            )).single['count']
            as int;

    expect(lotCount, 1);

    final persistedFinalLot = (await reopenedDb.query(
      'inventory_lots',
      where: 'product_id=? AND branch_id=?',
      whereArgs: [productId, branchId],
    )).single;

    expect(persistedFinalLot['available_quantity'], 7);
  });
}
