import 'package:intl/intl.dart';

final NumberFormat _currency = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
String formatMoney(int cents) => _currency.format(cents / 100);
int parseMoneyToCents(String value) {
  final normalized = value.replaceAll(',', '').replaceAll(r'$', '').trim();
  final decimal = double.parse(normalized);
  return (decimal * 100).round();
}
