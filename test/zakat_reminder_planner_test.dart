import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/services/zakat_engine.dart';
import 'package:moniz/services/zakat_reminder_planner.dart';

const planner = ZakatReminderPlanner();
const both = {
  ZakatReminderPlanner.dueSoonTopicId,
  ZakatReminderPlanner.dueTodayTopicId,
};
final now = DateTime(2026, 9, 5, 12);

ZakatResult _result({
  required ZakatSettings settings,
  List<ZakatAssetAssessment> assessments = const [],
}) {
  return ZakatResult(
    settings: settings,
    assessments: assessments,
    nisabThresholdUsd: 1000,
    eligibleWealthUsd: 5000,
    amountDueUsd: 125,
    canCalculate: true,
    isScheduleDue: false,
  );
}

ZakatAssetAssessment _gold(String id, DateTime? due, {String? excluded}) {
  return ZakatAssetAssessment(
    asset: Asset(id: id, type: AssetType.gold, amount: 20, unit: 'g'),
    valueUsd: 2000,
    isIncluded: excluded == null,
    nextDueDate: due,
    exclusionReason: excluded,
  );
}

void main() {
  test('nothing is scheduled while the owner has not asked for it', () {
    final plan = planner.plan(
      result: _result(
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2026, 12, 1)),
      ),
      subscribedTopicIds: const {},
      now: now,
    );

    expect(plan, isEmpty);
  });

  test('the Ramadan date produces one reminder for the whole portfolio', () {
    final plan = planner.plan(
      result: _result(
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2026, 12, 1)),
        assessments: [
          _gold('a', DateTime(2027, 1, 1)),
          _gold('b', DateTime(2027, 2, 1)),
        ],
      ),
      subscribedTopicIds: both,
      now: now,
    );

    // Per-holding anniversaries are irrelevant in this mode: everything
    // settles on the one date.
    expect(plan, hasLength(2));
    expect(plan.first.scheduledFor, DateTime(2026, 11, 24, 9));
    expect(plan.first.title, 'Zakat due in 7 days');
    expect(plan.first.body, 'Your zakat is due on 1 Dec 2026.');
    expect(plan.last.scheduledFor, DateTime(2026, 12, 1, 9));
    expect(plan.last.title, 'Zakat due today');
  });

  test('per-holding mode reminds about each holding by name', () {
    final plan = planner.plan(
      result: _result(
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        assessments: [_gold('gold', DateTime(2026, 10, 20))],
      ),
      subscribedTopicIds: {ZakatReminderPlanner.dueTodayTopicId},
      now: now,
    );

    expect(plan, hasLength(1));
    expect(plan.single.body, 'Zakat on your 20 g of gold is due today.');
  });

  test('a due date already past is not scheduled into the past', () {
    final plan = planner.plan(
      result: _result(
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        assessments: [_gold('gold', DateTime(2026, 8, 1))],
      ),
      subscribedTopicIds: both,
      now: now,
    );

    expect(plan, isEmpty);
  });

  test('the week-ahead warning is skipped once it is inside a week', () {
    final plan = planner.plan(
      result: _result(
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        assessments: [_gold('gold', DateTime(2026, 9, 9))],
      ),
      subscribedTopicIds: both,
      now: now,
    );

    // Its lead date is 2 Sep, already gone. The day itself still stands.
    expect(plan, hasLength(1));
    expect(plan.single.title, 'Zakat due today');
    expect(plan.single.scheduledFor, DateTime(2026, 9, 9, 9));
  });

  test('a sold holding owes nothing, so it is not reminded about', () {
    final plan = planner.plan(
      result: _result(
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        assessments: [
          _gold('sold', DateTime(2026, 11, 1), excluded: ZakatEngine.soldExclusion),
          _gold('kept', DateTime(2026, 11, 1)),
        ],
      ),
      subscribedTopicIds: {ZakatReminderPlanner.dueTodayTopicId},
      now: now,
    );

    expect(plan, hasLength(1));
    expect(plan.single.body, contains('20 g of gold'));
  });

  test('ids are stable per holding so rescheduling replaces, not stacks', () {
    List<int> idsFor(DateTime due) => planner
        .plan(
          result: _result(
            settings: const ZakatSettings(
              scheduleMode: ZakatScheduleMode.individualDueDates,
            ),
            assessments: [_gold('gold', due)],
          ),
          subscribedTopicIds: both,
          now: now,
        )
        .map((reminder) => reminder.id)
        .toList();

    // Same holding, a later anniversary: the pending notification is the same
    // slot moved, not a second one left behind.
    expect(idsFor(DateTime(2026, 11, 1)), idsFor(DateTime(2027, 3, 1)));
    expect(
      idsFor(DateTime(2026, 11, 1)).toSet().length,
      2,
      reason: 'the two topics must not collide with each other',
    );
  });

  test('a large ledger stays under the iOS pending-notification cap', () {
    final plan = planner.plan(
      result: _result(
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        assessments: [
          for (var i = 0; i < 60; i++)
            _gold('gold$i', DateTime(2026, 10, 1).add(Duration(days: i))),
        ],
      ),
      subscribedTopicIds: both,
      now: now,
    );

    expect(plan, hasLength(ZakatReminderPlanner.maxPending));
    // And what survives the cap is the soonest, not an arbitrary slice.
    final dates = plan.map((reminder) => reminder.scheduledFor).toList();
    final sorted = [...dates]..sort();
    expect(dates, sorted);
  });
}
