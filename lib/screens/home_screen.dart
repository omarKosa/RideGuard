import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/ride_summary.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_indicator.dart';
import 'bike_setup_screen.dart';
import 'ride/ride_screen.dart';
import 'safety_briefing_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _open(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bike = app.bike!;
    final cal = app.calibration;
    final last = app.lastRide;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RIDEGUARD',
                          style: AppText.display(24).copyWith(letterSpacing: 6),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${bike.model} · ${bike.ratedTopSpeedKmh.toStringAsFixed(0)} km/h',
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(16, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SyncIndicator(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) => switch (v) {
                      'bike' => _open(const BikeSetupScreen(editing: true)),
                      'calibrate' => _open(const SafetyBriefingScreen()),
                      _ => _open(const SettingsScreen()),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'bike', child: Text('Edit bike')),
                      PopupMenuItem(
                        value: 'calibrate',
                        child: Text('Redo init ride'),
                      ),
                      PopupMenuItem(value: 'settings', child: Text('Settings')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Center(child: _StartButton(pulse: _pulse)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Analysis window: last ${AppConfig.analysisWindowMinutes} min',
                  style: AppText.body(14, color: AppColors.textFaint),
                ),
              ),
              const SizedBox(height: 28),
              if (cal != null)
                SectionCard(
                  title: 'CALIBRATION',
                  trailing: Text(
                    '${(cal.quality * 100).toStringAsFixed(0)}%',
                    style: AppText.body(
                      14,
                      color: cal.quality >= 0.8
                          ? AppColors.green
                          : AppColors.amber,
                      weight: FontWeight.bold,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'TOP SPEED',
                          value: cal.achievedTopSpeedKmh == null
                              ? '—'
                              : cal.achievedTopSpeedKmh!.toStringAsFixed(0),
                          icon: Icons.speed,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'STOP TIME',
                          value: cal.brakeEvent == null
                              ? '—'
                              : '${cal.brakeEvent!.durationS.toStringAsFixed(1)}s',
                          icon: Icons.stop_circle_outlined,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'BRAKING',
                          value:
                              '${cal.brakingDecelMps2.toStringAsFixed(1)}m/s²',
                          icon: Icons.south,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              if (last != null) ...[
                const SizedBox(height: 16),
                _LastRideCard(summary: last),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(
              begin: 1.0,
              end: 1.15,
            ).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
            child: Container(
              width: 196,
              height: 196,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.red.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: Ink(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.red, AppColors.redDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.5),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: InkWell(
                key: const Key('start-ride'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RideScreen()),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.power_settings_new,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'START RIDE',
                      style: AppText.display(14).copyWith(letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastRideCard extends StatelessWidget {
  const _LastRideCard({required this.summary});

  final RideSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.totals;
    return SectionCard(
      title: 'LAST RIDE',
      trailing: Text(
        '${formatDuration(summary.duration)} · ${formatDistance(t.distanceM)}',
        style: AppText.body(13, color: AppColors.textMuted),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: [
          StatTile(
            label: 'MAX SPEED',
            value: t.maxSpeedKmh.toStringAsFixed(0),
            icon: Icons.speed,
          ),
          StatTile(
            label: 'MAX LEAN',
            value: '${t.maxLeanDeg.toStringAsFixed(0)}°',
            icon: Icons.screen_rotation_alt,
            color: AppColors.amber,
          ),
          StatTile(
            label: 'MAX STOP',
            value: '${t.maxStopTimeS.toStringAsFixed(1)}s',
            icon: Icons.stop_circle_outlined,
            color: AppColors.red,
          ),
        ],
      ),
    );
  }
}
