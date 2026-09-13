import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/design/components/app_components.dart';

void main() {
  Future<void> pumpWithSize(
    WidgetTester tester,
    Widget child, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: child)),
      ),
    );

    await tester.pump();
  }

  testWidgets('AppEmptyState no genera overflow con altura extrema', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;

    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = original);

    await pumpWithSize(
      tester,
      const AppEmptyState(message: 'No hay productos para mostrar.'),
      size: const Size(320, 80),
    );

    expect(
      errors.where(
        (e) => e.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });

  testWidgets('AppErrorState no genera overflow con altura extrema', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;

    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = original);

    await pumpWithSize(
      tester,
      const AppErrorState(message: 'No se pudieron cargar los datos.'),
      size: const Size(320, 80),
    );

    expect(
      errors.where(
        (e) => e.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });

  testWidgets('AppLoadingState no genera overflow con altura extrema', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;

    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = original);

    await pumpWithSize(
      tester,
      const AppLoadingState(label: 'Cargando…'),
      size: const Size(320, 80),
    );

    expect(
      errors.where(
        (e) => e.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });
}
