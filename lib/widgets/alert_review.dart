import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../theme/app_theme.dart';
import 'alert_card.dart';

/// After a ride: one card per alert asking whether it really happened.
/// Swipe right or YES, swipe left or NO; SKIP ends the review and leaves
/// the remaining alerts unanswered.
class AlertReview extends StatefulWidget {
  const AlertReview({
    super.key,
    required this.incidents,
    required this.onLabel,
    required this.onDone,
  });

  final List<Incident> incidents;

  /// Stores and uploads an answer; returns the labelled incident.
  final Future<Incident> Function(Incident, RiderLabel) onLabel;

  /// Every incident, in order, labelled where the rider answered.
  final ValueChanged<List<Incident>> onDone;

  @override
  State<AlertReview> createState() => AlertReviewState();
}

class AlertReviewState extends State<AlertReview>
    with SingleTickerProviderStateMixin {
  late final List<Incident> _incidents = List.of(widget.incidents);
  int _index = 0;
  bool _done = false;

  /// Answers are saved one after another, in order.
  Future<void> _saving = Future.value();

  /// Swipe progress of the current card: positive towards YES.
  double _drag = 0;

  /// A tapped answer throws the card off like a swipe would.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(() => setState(() => _drag = _flyingTo * _fly.value));

  /// +1 towards YES, -1 towards NO, 0 while no card is flying.
  double _flyingTo = 0;

  @override
  void initState() {
    super.initState();
    // Nothing to ask: done straight away.
    if (_incidents.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  Future<void> _tap(RiderLabel label) async {
    if (_done || _flyingTo != 0 || _index >= _incidents.length) return;
    _flyingTo = label == RiderLabel.yes ? 1 : -1;
    try {
      await _fly.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    _flyingTo = 0;
    _fly.value = 0;
    _answer(label);
  }

  void _answer(RiderLabel label) {
    if (_done || _index >= _incidents.length) return;
    final i = _index;
    _saving = _saving.then((_) async {
      try {
        _incidents[i] = await widget.onLabel(_incidents[i], label);
      } catch (e, st) {
        // The alert stays unanswered; the review goes on.
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: st, library: 'ride guard'),
        );
      }
    });
    setState(() {
      _index++;
      _drag = 0;
    });
    if (_index == _incidents.length) _finish();
  }

  /// Ends the review now; alerts not answered yet stay unlabelled. A card
  /// already flying off keeps its answer.
  void skip() {
    if (_flyingTo != 0) {
      final label = _flyingTo > 0 ? RiderLabel.yes : RiderLabel.no;
      _fly.stop();
      _flyingTo = 0;
      _answer(label);
    }
    _finish();
  }

  Future<void> _finish() async {
    if (_done) return;
    setState(() => _done = true);
    await _saving;
    if (mounted) widget.onDone(List.unmodifiable(_incidents));
  }

  @override
  Widget build(BuildContext context) {
    final n = _incidents.length;
    if (_done || _index >= n) return const SizedBox.shrink();
    final incident = _incidents[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('ALERT ${_index + 1} OF $n', style: AppText.label(13)),
              const Spacer(),
              OutlinedButton(
                key: const Key('alert-skip'),
                onPressed: skip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('SKIP'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AlertDots(count: n, on: _index + 1),
          ),
          Expanded(
            child: KeyedSubtree(
              // A fresh card (and Dismissible) per alert.
              key: ValueKey(_index),
              child: _SlideIn(
                child: Dismissible(
                  key: const Key('alert-card'),
                  direction: _flyingTo != 0
                      ? DismissDirection.none
                      : DismissDirection.horizontal,
                  resizeDuration: null,
                  onUpdate: (d) => setState(
                    () => _drag = d.direction == DismissDirection.startToEnd
                        ? d.progress
                        : -d.progress,
                  ),
                  onDismissed: (d) => _answer(
                    d == DismissDirection.startToEnd
                        ? RiderLabel.yes
                        : RiderLabel.no,
                  ),
                  child: FractionalTranslation(
                    translation: Offset(_flyingTo * _fly.value * 1.3, 0),
                    child: AlertCard(incident: incident, drag: _drag),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              AlertAnswerButton(
                key: const Key('alert-no'),
                label: 'NO',
                color: AppColors.amber,
                onPressed: () => _tap(RiderLabel.no),
              ),
              const SizedBox(width: 12),
              AlertAnswerButton(
                key: const Key('alert-yes'),
                label: 'YES',
                color: AppColors.green,
                onPressed: () => _tap(RiderLabel.yes),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'or swipe ← →',
            textAlign: TextAlign.center,
            style: AppText.body(12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}

/// The next card rises into place.
class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 40),
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
    ),
    child: child,
  );
}
