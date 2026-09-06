import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/recurring_entry.dart';
import '../services/recurrence_planner.dart';
import 'money_entry_provider.dart';

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

/// Writes whatever the current rules owe, through the providers so the screen
/// updates without a restart.
///
/// Startup does the same thing straight against the boxes. This exists for the
/// moments in between: saving a rule that started last month should fill in
/// those entries now, not the next time the app is opened.
Future<void> applyDueRecurrences(WidgetRef ref, {DateTime? now}) async {
  const planner = RecurrencePlanner();
  final rules = ref.read(recurringEntryProvider);
  final entryNotifier = ref.read(moneyEntryProvider.notifier);
  final ruleNotifier = ref.read(recurringEntryProvider.notifier);
  final at = now ?? DateTime.now();

  for (final rule in rules) {
    final result = planner.materialise(rule: rule, now: at);
    if (result.entries.isEmpty) continue;
    for (final entry in result.entries) {
      await entryNotifier.addEntry(entry);
    }
    await ruleNotifier.upsert(result.rule);
  }
}
