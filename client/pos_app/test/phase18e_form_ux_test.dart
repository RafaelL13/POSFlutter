import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/shared/presentation/database_list_screen.dart';

void main() {
  Widget harness({List<TextFormFieldSpec>? fields}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder:
            (context) => ElevatedButton(
              onPressed:
                  () => configuredTextForm(
                    context,
                    'Formulario de prueba',
                    fields ?? const [TextFormFieldSpec('Nombre')],
                  ),
              child: const Text('Abrir'),
            ),
      ),
    ),
  );

  testWidgets('muestra validación junto a un campo obligatorio', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
    expect(find.text('Formulario de prueba'), findsOneWidget);
  });

  testWidgets('rechaza cantidades no numéricas y no positivas', (tester) async {
    await tester.pumpWidget(
      harness(fields: const [TextFormFieldSpec('Cantidad', numeric: true)]),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Ingresa un número válido.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('El valor debe ser mayor que cero.'), findsOneWidget);
  });

  testWidgets('un ajuste de inventario permite cantidad negativa', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        fields: const [
          TextFormFieldSpec(
            'Cantidad (+/-)',
            numeric: true,
            allowNegative: true,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-2');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Formulario de prueba'), findsNothing);
  });
}
