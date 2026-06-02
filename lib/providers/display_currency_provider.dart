import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../services/currency_converter.dart';

class DisplayCurrencyNotifier extends StateNotifier<String> {
  DisplayCurrencyNotifier({Box<dynamic>? preferencesBox})
    : _preferencesBox = preferencesBox ?? Hive.box<dynamic>('uiPreferences'),
      super(_read(preferencesBox ?? Hive.box<dynamic>('uiPreferences')));

  static const _displayCurrencyKey = 'displayCurrency';
  final Box<dynamic> _preferencesBox;

  static String _read(Box<dynamic> box) {
    final value = box.get(_displayCurrencyKey) as String?;
    final normalized = CurrencyConverter.normalize(value);
    return CurrencyConverter.isSupported(normalized)
        ? normalized
        : CurrencyConverter.defaultCurrency;
  }

  Future<void> setCurrency(String currency) async {
    final normalized = CurrencyConverter.normalize(currency);
    if (!CurrencyConverter.isSupported(normalized)) return;
    state = normalized;
    await _preferencesBox.put(_displayCurrencyKey, normalized);
  }
}

final displayCurrencyProvider =
    StateNotifierProvider<DisplayCurrencyNotifier, String>(
      (ref) => DisplayCurrencyNotifier(),
    );
