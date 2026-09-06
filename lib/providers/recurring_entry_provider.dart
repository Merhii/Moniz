import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/recurring_entry.dart';

class RecurringEntryNotifier extends StateNotifier<List<RecurringEntry>> {
  RecurringEntryNotifier({Box<RecurringEntry>? ruleBox})
    : ruleBox = ruleBox ?? Hive.box<RecurringEntry>('moneyRecurrences'),
      super(
        _sorted(
          (ruleBox ?? Hive.box<RecurringEntry>('moneyRecurrences')).values,
        ),
      );

  final Box<RecurringEntry> ruleBox;

  void loadRules() {
    state = _sorted(ruleBox.values);
  }

  Future<void> upsert(RecurringEntry rule) async {
    await ruleBox.put(rule.id, rule);
    loadRules();
  }

  Future<void> remove(String id) async {
    await ruleBox.delete(id);
    loadRules();
  }

  Future<void> setPaused(String id, bool isPaused) async {
    final existing = ruleBox.get(id);
    if (existing == null) return;
    await ruleBox.put(id, existing.copyWith(isPaused: isPaused));
    loadRules();
  }

  static List<RecurringEntry> _sorted(Iterable<RecurringEntry> rules) {
    final list = rules.toList()
      ..sort((a, b) {
        final byPaused = (a.isPaused ? 1 : 0).compareTo(b.isPaused ? 1 : 0);
        if (byPaused != 0) return byPaused;
        final byDay = a.dayOfPeriod.compareTo(b.dayOfPeriod);
        return byDay != 0 ? byDay : a.amount.compareTo(b.amount);
      });
    return List.unmodifiable(list);
  }
}

final recurringEntryProvider =
    StateNotifierProvider<RecurringEntryNotifier, List<RecurringEntry>>(
      (ref) => RecurringEntryNotifier(),
    );
