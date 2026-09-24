import 'dart:convert';

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

  test(
    'P001 import 10 at 100, sell 3 at 140, leaves 7 with exact FIFO profit',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      final db = await database.open();
      final now = DateTime.utc(2026, 9, 24).toIso8601String();

      final businessId = await db.insert('businesses', {
        'global_id': 'business-p001',
        'name': 'P001 Business',
        'created_at': now,
        'updated_at': now,
      });

      final branchId = await db.insert('branches', {
        'global_id': 'branch-p001',
        'business_id': businessId,
        'name': 'Main',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('devices', {
        'global_id': 'device-p001',
        'branch_id': branchId,
        'name': 'POS',
        'mode': 'PointOfSale',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('users', {
        'global_id': 'user-p001',
        'business_id': businessId,
        'name': 'Administrator',
        'username': 'admin-p001',
        'password_hash': 'h',
        'password_salt': 's',
        'role': 'Administrator',
        'created_at': now,
        'updated_at': now,
      });

      for (final entry in {
        'local_device_global_id': 'device-p001',
        'active_user_global_id': 'user-p001',
      }.entries) {
        await db.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        });
      }

      final preview = CatalogImportCsv.parse(
        utf8.encode(
          'SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial\n'
          'P001,Producto P001,General,Proveedor P001,100.00,140.00,10\n',
        ),
      );

      expect(preview.isValid, isTrue);
      expect(preview.rows, hasLength(1));
      expect(preview.rows.single.costCents, 10000);
      expect(preview.rows.single.priceCents, 14000);
      expect(preview.rows.single.quantity, 10);

      final importGlobalId = await InitialInventoryRepository(database).import(
        preview: preview,
        policy: ExistingCatalogPolicy.skip,
        sourceName: 'P001.csv',
      );

      expect(importGlobalId, isNotEmpty);

      final product = (await db.query(
        'products',
        where: 'business_id=? AND code=?',
        whereArgs: [businessId, 'P001'],
      )).single;

      final productId = product['id'] as int;
      final productGlobalId = product['global_id'] as String;

      expect(product['sale_price_cents'], 14000);

      var lots = await db.query(
        'inventory_lots',
        where: 'product_id=? AND branch_id=?',
        whereArgs: [productId, branchId],
      );

      expect(lots, hasLength(1));
      expect(lots.single['initial_quantity'], 10);
      expect(lots.single['available_quantity'], 10);
      expect(lots.single['unit_cost_cents'], 10000);

      final importQueueBeforeSale = await db.query(
        'sync_queue',
        where: "entity_type='InitialInventory'",
      );
      expect(importQueueBeforeSale, hasLength(1));

      final sale = await PosRepository(database).completeSale(
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

      final saleRow = (await db.query(
        'sales',
        where: 'global_id=?',
        whereArgs: [sale.globalId],
      )).single;

      expect(saleRow['status'], 'Confirmed');
      expect(saleRow['subtotal_cents'], 42000);
      expect(saleRow['total_cents'], 42000);
      expect(saleRow['fifo_cost_cents'], 30000);
      expect(saleRow['gross_profit_cents'], 12000);

      lots = await db.query(
        'inventory_lots',
        where: 'product_id=? AND branch_id=?',
        whereArgs: [productId, branchId],
      );

      expect(lots.single['available_quantity'], 7);

      final saleDetail = (await db.query(
        'sale_details',
        where: 'sale_id=?',
        whereArgs: [saleRow['id']],
      )).single;

      expect(saleDetail['quantity'], 3);
      expect(saleDetail['unit_price_cents'], 14000);
      expect(saleDetail['total_cents'], 42000);
      expect(saleDetail['fifo_cost_cents'], 30000);

      final allocations = await db.query(
        'sale_detail_lots',
        where: 'sale_detail_id=?',
        whereArgs: [saleDetail['id']],
      );

      expect(allocations, hasLength(1));
      expect(allocations.single['quantity'], 3);
      expect(allocations.single['unit_cost_cents'], 10000);
      expect(allocations.single['total_cost_cents'], 30000);

      final movements = await db.query(
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

      final payments = await db.query(
        'sale_payments',
        where: 'sale_id=?',
        whereArgs: [saleRow['id']],
      );

      expect(payments, hasLength(1));
      expect(payments.single['method'], PaymentMethod.card.storageValue);
      expect(payments.single['amount_cents'], 42000);

      final cashMovements = await db.query(
        'cash_movements',
        where: "type='Sale' AND reference_global_id=?",
        whereArgs: [sale.globalId],
      );

      expect(cashMovements, isEmpty);

      final saleQueue = (await db.query(
        'sync_queue',
        where: "entity_type='Sale' AND entity_global_id=?",
        whereArgs: [sale.globalId],
      )).single;

      expect(saleQueue['payload_version'], 2);

      final salePayload = jsonDecode(
        saleQueue['payload_json'] as String,
      ) as Map<String, dynamic>;

      expect(salePayload['totalCents'], 42000);
      expect(salePayload['fifoCostCents'], 30000);
      expect(salePayload['grossProfitCents'], 12000);

      final payloadLines = salePayload['lines'] as List<dynamic>;
      expect(payloadLines, hasLength(1));

      final payloadLine = payloadLines.single as Map<String, dynamic>;
      expect(payloadLine['quantity'], 3);
      expect(payloadLine['unitPriceCents'], 14000);
      expect(payloadLine['fifoCostCents'], 30000);

      final payloadLots = payloadLine['lots'] as List<dynamic>;
      expect(payloadLots, hasLength(1));

      final payloadLot = payloadLots.single as Map<String, dynamic>;
      expect(payloadLot['quantity'], 3);
      expect(payloadLot['unitCostCents'], 10000);
      expect(payloadLot['totalCostCents'], 30000);

      final saleQueueCount =
          (await db.rawQuery(
                "SELECT COUNT(*) AS count FROM sync_queue "
                "WHERE entity_type='Sale' AND entity_global_id=?",
                [sale.globalId],
              )).single['count']
              as int;

      expect(saleQueueCount, 1);

      final duplicateImportGlobalId = await InitialInventoryRepository(database)
          .import(
            preview: preview,
            policy: ExistingCatalogPolicy.skip,
            sourceName: 'P001-reimport.csv',
          );

      expect(duplicateImportGlobalId, importGlobalId);

      final importCount =
          (await db.rawQuery(
                'SELECT COUNT(*) AS count FROM initial_inventory_imports '
                'WHERE business_id=? AND branch_id=? AND source_fingerprint=?',
                [businessId, branchId, preview.fingerprint],
              )).single['count']
              as int;

      expect(importCount, 1);

      final lotCount =
          (await db.rawQuery(
                'SELECT COUNT(*) AS count FROM inventory_lots '
                'WHERE product_id=? AND branch_id=?',
                [productId, branchId],
              )).single['count']
              as int;

      expect(lotCount, 1);

      final finalLot = (await db.query(
        'inventory_lots',
        where: 'product_id=? AND branch_id=?',
        whereArgs: [productId, branchId],
      )).single;

      expect(finalLot['available_quantity'], 7);
    },
  );
}
