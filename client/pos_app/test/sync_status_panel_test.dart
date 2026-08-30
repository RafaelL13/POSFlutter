import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/sync/presentation/sync_status_panel.dart';
import 'package:pos_app/sync/sync_health.dart';

void main() {
  testWidgets('pending status is visible', (tester) async {
    await _pump(
      tester,
      const SyncSummary(
        pendingCount: 4,
        retryingCount: 0,
        attentionCount: 0,
        conflictCount: 0,
        isOnline: true,
        isSyncing: false,
      ),
    );
    expect(find.text('4 cambios pendientes'), findsOneWidget);
  });

  testWidgets('offline status preserves pending count', (tester) async {
    await _pump(
      tester,
      const SyncSummary(
        pendingCount: 4,
        retryingCount: 0,
        attentionCount: 0,
        conflictCount: 0,
        isOnline: false,
        isSyncing: false,
      ),
    );
    expect(find.text('Sin conexión — 4 cambios pendientes'), findsOneWidget);
  });

  testWidgets('requires attention status is visible', (tester) async {
    await _pump(
      tester,
      const SyncSummary(
        pendingCount: 0,
        retryingCount: 0,
        attentionCount: 2,
        conflictCount: 0,
        isOnline: true,
        isSyncing: false,
      ),
    );
    expect(find.text('2 operaciones requieren atención'), findsOneWidget);
    expect(find.text('Requiere atención: 2'), findsOneWidget);
  });

  testWidgets('conflict status is visible', (tester) async {
    await _pump(
      tester,
      const SyncSummary(
        pendingCount: 0,
        retryingCount: 0,
        attentionCount: 1,
        conflictCount: 1,
        isOnline: true,
        isSyncing: false,
      ),
    );
    expect(find.text('1 conflictos pendientes'), findsOneWidget);
    expect(find.textContaining('Conflictos: 1'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, SyncSummary summary) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusPanel(summary: summary)),
      ),
    );
