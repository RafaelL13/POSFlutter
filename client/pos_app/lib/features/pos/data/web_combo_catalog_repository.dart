import 'package:pos_app/core/network/cloud_api_client.dart';

final class WebComboComponent {
  const WebComboComponent({required this.productGlobalId, required this.quantity});
  final String productGlobalId;
  final int quantity;
}

final class WebComboCatalogItem {
  const WebComboCatalogItem({
    required this.comboGlobalId,
    required this.code,
    required this.name,
    required this.priceCents,
    required this.serverVersion,
    required this.components,
  });
  final String comboGlobalId;
  final String code;
  final String name;
  final int priceCents;
  final int serverVersion;
  final List<WebComboComponent> components;

  static WebComboCatalogItem fromJson(Map<String, Object?> raw) {
    String str(String key) => raw[key] is String ? raw[key] as String :
        (throw FormatException('Campo requerido: $key'));
    int number(String key) => raw[key] is int ? raw[key] as int :
        (throw FormatException('Número requerido: $key'));
    final parts = raw['components'];
    if (parts is! List || parts.isEmpty) throw const FormatException('Combo sin componentes');
    final items = parts.map((entry) {
      if (entry is! Map<String, Object?>) throw const FormatException('Componente inválido');
      final id = entry['productGlobalId'];
      final qty = entry['quantity'];
      if (id is! String || id.isEmpty || qty is! int || qty < 1) {
        throw const FormatException('Componente inválido');
      }
      return WebComboComponent(productGlobalId: id, quantity: qty);
    }).toList(growable: false);
    final item = WebComboCatalogItem(
      comboGlobalId: str('comboGlobalId'), code: str('code'),
      name: str('name'), priceCents: number('priceCents'),
      serverVersion: number('serverVersion'), components: items,
    );
    if (item.comboGlobalId.isEmpty || item.serverVersion < 1 || item.priceCents <= 0) {
      throw const FormatException('Combo inválido');
    }
    return item;
  }
}

final class WebComboCatalogRepository {
  const WebComboCatalogRepository(this.client);
  final JsonApiClient client;

  Future<List<WebComboCatalogItem>> load() async {
    final response = await client.get('/api/combos/catalog');
    final raw = response['items'];
    if (raw is! List) throw const FormatException('Catálogo de combos inválido');
    return raw.map((item) {
      if (item is! Map<String, Object?>) throw const FormatException('Combo inválido');
      return WebComboCatalogItem.fromJson(item);
    }).toList(growable: false);
  }
}
