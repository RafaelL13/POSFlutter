import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/design/app_breakpoints.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/core/design/components/app_components.dart';

void main() {
  test('theme builds with the professional Material 3 system', () {
    final theme = AppTheme.light;
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, isNot(Colors.blue));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
  });

  test('responsive breakpoints classify supported targets', () {
    expect(AppBreakpoints.ofWidth(390), AppLayoutSize.compact);
    expect(AppBreakpoints.ofWidth(800), AppLayoutSize.medium);
    expect(AppBreakpoints.ofWidth(1280), AppLayoutSize.expanded);
  });

  testWidgets('global buttons expose labels and callbacks', (tester) async {
    var primary = false;
    var secondary = false;
    await tester.pumpWidget(
      _app(
        Row(
          children: [
            AppPrimaryButton(label: 'Guardar', onPressed: () => primary = true),
            AppSecondaryButton(
              label: 'Cancelar',
              onPressed: () => secondary = true,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.tap(find.text('Cancelar'));
    expect(primary, isTrue);
    expect(secondary, isTrue);
  });

  testWidgets('status chip combines icon and text', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppStatusChip(label: 'Sincronizado', status: AppStatus.synced),
      ),
    );
    expect(find.text('Sincronizado'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('empty and error states are human readable', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            AppEmptyState(message: 'No hay productos registrados.'),
            AppErrorState(),
          ],
        ),
      ),
    );
    expect(find.text('No hay productos registrados.'), findsOneWidget);
    expect(find.text('No se pudieron cargar los datos.'), findsOneWidget);
  });

  for (final size in const [Size(390, 844), Size(800, 1280), Size(1280, 800)]) {
    testWidgets(
      'page layout renders without overflow at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _app(
            const AppPage(
              title: 'Productos',
              subtitle: 'Administra el catálogo.',
              showNavigation: false,
              body: AppEmptyState(message: 'No hay productos registrados.'),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Productos'), findsOneWidget);
      },
    );
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);
