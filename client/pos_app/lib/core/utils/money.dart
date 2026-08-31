import 'package:intl/intl.dart';

final NumberFormat _currency = NumberFormat.currency(
  locale: 'es_MX',
  symbol: r'$',
);
String formatMoney(int cents) => _currency.format(cents / 100);
int parseMoneyToCents(String value) {
  final normalized = value.replaceAll(r'$', '').replaceAll(' ', '').trim();
  if (normalized.isEmpty) throw const FormatException('Monto vacío.');

  final decimalSeparator =
      normalized.lastIndexOf('.') > normalized.lastIndexOf(',')
          ? '.'
          : normalized.contains(',')
          ? ','
          : null;
  final parts =
      decimalSeparator == null
          ? [normalized]
          : normalized.split(decimalSeparator);
  if (parts.length > 2) throw const FormatException('Monto inválido.');

  final groupingSeparator = decimalSeparator == '.' ? ',' : '.';
  final wholeText = parts.first.replaceAll(groupingSeparator, '');
  final negative = wholeText.startsWith('-');
  final digits = negative ? wholeText.substring(1) : wholeText;
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
    throw const FormatException('Monto inválido.');
  }

  final fraction = parts.length == 1 ? '' : parts.last;
  if (!RegExp(r'^\d{0,2}$').hasMatch(fraction)) {
    throw const FormatException('Usa como máximo dos decimales.');
  }
  final cents =
      int.parse(digits) * 100 +
      int.parse(
        fraction.padRight(2, '0').isEmpty ? '0' : fraction.padRight(2, '0'),
      );
  return negative ? -cents : cents;
}
