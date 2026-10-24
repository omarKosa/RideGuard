import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../widgets/alert_review.dart';
import '../widgets/common.dart';

/// The alert cards as their own screen; pops with the incidents, labelled
/// where the rider answered. System back is SKIP.
class AlertReviewScreen extends StatefulWidget {
  const AlertReviewScreen({
    super.key,
    required this.incidents,
    required this.onLabel,
  });

  final List<Incident> incidents;
  final Future<Incident> Function(Incident, RiderLabel) onLabel;

  @override
  State<AlertReviewScreen> createState() => _AlertReviewScreenState();
}

class _AlertReviewScreenState extends State<AlertReviewScreen> {
  final _review = GlobalKey<AlertReviewState>();

  @override
  Widget build(BuildContext context) {
    return PopScope<List<Incident>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _review.currentState?.skip();
      },
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: AlertReview(
              key: _review,
              incidents: widget.incidents,
              onLabel: widget.onLabel,
              onDone: (labelled) => Navigator.of(context).pop(labelled),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks about each of [incidents] when there are any; returns them with
/// the rider's answers (unchanged when there was nothing to ask).
Future<List<Incident>> reviewAlerts(
  NavigatorState navigator,
  List<Incident> incidents,
  Future<Incident> Function(Incident, RiderLabel) onLabel,
) async {
  if (incidents.isEmpty) return incidents;
  final labelled = await navigator.push<List<Incident>>(
    MaterialPageRoute(
      builder: (_) => AlertReviewScreen(incidents: incidents, onLabel: onLabel),
    ),
  );
  return labelled ?? incidents;
}
