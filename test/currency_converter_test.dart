import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/services/currency_converter.dart';

void main() {
  group('CurrencyConverter formatting', () {
    test('formats money with thousands separators', () {
      expect(CurrencyConverter.formatMoney(1234567.8, 'USD'), r'$1,234,567.80');
      expect(
        CurrencyConverter.formatMoney(1234567, 'AED', decimals: 0),
        'AED 1,234,567',
      );
      expect(CurrencyConverter.formatMoney(98765.4321, 'EUR'), 'EUR 98,765.43');
    });

    test('formats plain numbers with trimmed decimals', () {
      expect(CurrencyConverter.formatNumber(1234567), '1,234,567');
      expect(CurrencyConverter.formatNumber(1234567.25), '1,234,567.25');
      expect(
        CurrencyConverter.formatNumber(1234567.2, decimals: 3),
        '1,234,567.200',
      );
    });
  });
}
