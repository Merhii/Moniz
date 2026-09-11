import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// The things the tour points at, in the order it points at them.
///
/// All of them live on Today or in the nav bar, so the tour never has to move
/// somebody between tabs to finish a sentence.
enum TourStop { period, addEntry, repeats, wealth, zakat }

/// Where each stop is on screen.
///
/// The targets already carry value keys that tests and the driver rely on, so
/// the tour hangs its own [GlobalKey] beside them rather than replacing those.
class TourAnchors {
  TourAnchors()
    : _keys = {
        for (final stop in TourStop.values)
          stop: GlobalKey(debugLabel: 'tour_${stop.name}'),
      };

  final Map<TourStop, GlobalKey> _keys;

  GlobalKey keyFor(TourStop stop) => _keys[stop]!;

  /// The target's rectangle, or null when it is not on screen.
  ///
  /// Null is an ordinary answer, not a failure: a step with nothing to point
  /// at is skipped rather than drawn as a hole over empty background.
  Rect? rectFor(TourStop stop) {
    final context = _keys[stop]!.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

final tourAnchorsProvider = Provider<TourAnchors>((ref) => TourAnchors());

/// Whether the tour has already been shown.
///
/// Stored rather than held in memory: a walkthrough that reappears on every
/// launch stops being help and becomes an obstacle.
class TourSeenNotifier extends StateNotifier<bool> {
  TourSeenNotifier({Box<dynamic>? preferencesBox})
    : _box = preferencesBox ?? Hive.box<dynamic>('uiPreferences'),
      super(
        (preferencesBox ?? Hive.box<dynamic>('uiPreferences')).get(
              storageKey,
              defaultValue: false,
            )
            as bool,
      );

  @visibleForTesting
  static const storageKey = 'has_seen_coach_tour';

  final Box<dynamic> _box;

  Future<void> markSeen() async {
    state = true;
    await _box.put(storageKey, true);
  }

  /// Runs it again from the top.
  ///
  /// A walkthrough you can only ever see once is no use to somebody who
  /// skipped it in the first ten seconds and wants it back a week later.
  Future<void> replay() async {
    state = false;
    await _box.put(storageKey, false);
  }
}

final tourSeenProvider = StateNotifierProvider<TourSeenNotifier, bool>(
  (ref) => TourSeenNotifier(),
);
