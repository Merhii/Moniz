import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/coach_tour_provider.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

/// Marks a widget as something the tour can point at.
///
/// Wraps rather than re-keys, so the value keys the tests and the driver use
/// stay exactly where they were.
class TourAnchor extends ConsumerWidget {
  const TourAnchor({super.key, required this.stop, required this.child});

  final TourStop stop;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: ref.read(tourAnchorsProvider).keyFor(stop),
      child: child,
    );
  }
}

class _Step {
  const _Step({required this.stop, required this.title, required this.body});

  final TourStop stop;
  final String title;
  final String body;
}

/// What the tour teaches, which is the loop rather than the buttons.
///
/// Somebody can work out what a button labelled "Add entry" does. What they
/// cannot work out is that the three tabs are one thing: what you spend feeds
/// what you own, and both feed what you owe.
const _steps = <_Step>[
  _Step(
    stop: TourStop.period,
    title: 'Today, this week, this month',
    body: 'The total above follows whichever one you pick.',
  ),
  _Step(
    stop: TourStop.addEntry,
    title: 'Three taps',
    body: 'Amount, category, save. The keyboard is already up when it opens.',
  ),
  _Step(
    stop: TourStop.repeats,
    title: 'Anything regular',
    body:
        'Salary, rent, a subscription. Set it up once and Moniz enters it for '
        'you, dated to when it fell due.',
  ),
  _Step(
    stop: TourStop.wealth,
    title: 'What you own',
    body: 'Gold, silver and cash, valued at today\'s prices.',
  ),
  _Step(
    stop: TourStop.zakat,
    title: 'What you owe',
    body:
        'Moniz reads your holdings and your wallets and works the zakat out '
        'against nisab.',
  ),
];

class CoachTour extends ConsumerStatefulWidget {
  const CoachTour({super.key, required this.isActive});

  /// Only true on Today. Every stop is either on that page or in the nav bar,
  /// and cutting a hole over a page nobody is looking at would be nonsense.
  final bool isActive;

  @override
  ConsumerState<CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends ConsumerState<CoachTour> {
  var _step = 0;

  /// Anchors have no position until the frame they are laid out in, so the
  /// first frame is spent waiting rather than deciding a step has no target.
  var _laidOut = false;

  /// The step actually being drawn, which can be past [_step] when something
  /// in between had nowhere to point.
  ///
  /// Written during build and never through setState: nudging state from a
  /// build in order to re-render is how a rebuild loop starts, and an anchor
  /// that flickers in and out of the tree would keep it spinning.
  var _showing = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _laidOut = true);
    });
  }

  Future<void> _finish() async {
    await ref.read(tourSeenProvider.notifier).markSeen();
    if (mounted) setState(() => _step = 0);
  }

  void _next() {
    if (_showing >= _steps.length - 1) {
      _finish();
      return;
    }
    setState(() => _step = _showing + 1);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive || ref.watch(tourSeenProvider) || !_laidOut) {
      return const SizedBox.shrink();
    }

    final anchors = ref.watch(tourAnchorsProvider);

    // Walk forward past anything that is not on screen — a shorter tour is
    // better than one that points at nothing.
    var index = _step;
    Rect? target;
    while (index < _steps.length) {
      target = anchors.rectFor(_steps[index].stop);
      if (target != null) break;
      index += 1;
    }
    if (target == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
      return const SizedBox.shrink();
    }
    _showing = index;
    final step = _steps[index];
    final colors = context.kinetic;
    final screen = MediaQuery.sizeOf(context);
    // Kept inside the screen: a left-aligned control sits hard against the
    // edge, and inflating it pushes the ring off the side where the rounded
    // corners get sliced away.
    const margin = 6.0;
    final padded = target.inflate(10);
    final hole = Rect.fromLTRB(
      math.max(margin, padded.left),
      math.max(margin, padded.top),
      math.min(screen.width - margin, padded.right),
      math.min(screen.height - margin, padded.bottom),
    );
    // Below the target when it sits in the top half, above it otherwise, so
    // the card never covers the thing it is describing.
    final below = hole.center.dy < screen.height / 2;

    return Material(
      key: const Key('coach_tour'),
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Swallows taps as well as painting: the app underneath should not
          // react to somebody dismissing the card.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: CustomPaint(
                painter: _SpotlightPainter(hole: hole, accent: colors.accent),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: below ? hole.bottom + 18 : null,
            bottom: below ? null : screen.height - hole.top + 18,
            child: _TourCard(
              step: step,
              index: index,
              total: _steps.length,
              onNext: _next,
              onSkip: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final _Step step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isLast = index == total - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.muted.withValues(alpha: 0.98),
          colors.background,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            KineticText(
              step.title,
              style: AppTheme.titleStyle(colors).copyWith(fontSize: 19),
            ),
            const SizedBox(height: 8),
            KineticText(
              step.body,
              key: const Key('coach_tour_body'),
              uppercase: false,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                KineticText(
                  '${index + 1} of $total',
                  muted: true,
                  style: AppTheme.labelStyle(colors).copyWith(fontSize: 11),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('coach_tour_skip'),
                  onPressed: onSkip,
                  child: KineticText(
                    'Skip',
                    uppercase: false,
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(color: colors.mutedForeground, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 4),
                BrutalistButton(
                  key: const Key('coach_tour_next'),
                  label: isLast ? 'Done' : 'Next',
                  tone: BrutalistButtonTone.primary,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.accent});

  final Rect hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(cutout),
    );
    canvas.drawPath(scrim, Paint()..color = const Color(0xCC04101F));
    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.accent != accent;
}
