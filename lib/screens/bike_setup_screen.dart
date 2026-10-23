import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/bike_profile.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'safety_briefing_screen.dart';

/// First screen of the app: which bike, and how fast can it go.
class BikeSetupScreen extends StatefulWidget {
  const BikeSetupScreen({super.key, this.editing = false});

  /// Editing an existing bike from Home (pops back) rather than first-run
  /// onboarding (continues to calibration).
  final bool editing;

  @override
  State<BikeSetupScreen> createState() => _BikeSetupScreenState();
}

class _BikeSetupScreenState extends State<BikeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _model;
  late final TextEditingController _topSpeed;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bike = context.read<AppState>().bike;
    _model = TextEditingController(text: bike?.model ?? '');
    _topSpeed = TextEditingController(
      text: bike == null ? '' : bike.ratedTopSpeedKmh.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _model.dispose();
    _topSpeed.dispose();
    super.dispose();
  }

  static String? validateModel(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Enter your motorcycle model';
    if (v.length > 80) return 'Keep it under 80 characters';
    return null;
  }

  static String? validateTopSpeed(String? value) {
    final v = double.tryParse(value?.trim() ?? '');
    if (v == null) return 'Enter a speed in km/h';
    if (v < BikeProfile.minTopSpeedKmh || v > BikeProfile.maxTopSpeedKmh) {
      return 'Between ${BikeProfile.minTopSpeedKmh.toInt()} and '
          '${BikeProfile.maxTopSpeedKmh.toInt()} km/h';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    await app.saveBike(
      model: _model.text,
      ratedTopSpeedKmh: double.parse(_topSpeed.text.trim()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.editing) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SafetyBriefingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('EDIT BIKE')) : null,
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.editing) ...[
                        const _Logo(),
                        const SizedBox(height: 32),
                        Text(
                          'SET UP YOUR BIKE',
                          textAlign: TextAlign.center,
                          style: AppText.display(20),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RideGuard calibrates to your motorcycle and the way '
                          'your phone is mounted.',
                          textAlign: TextAlign.center,
                          style: AppText.body(16, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 32),
                      ],
                      TextFormField(
                        key: const Key('model-field'),
                        controller: _model,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        style: AppText.body(18),
                        decoration: const InputDecoration(
                          labelText: 'Motorcycle model',
                          hintText: 'e.g. Yamaha MT-07',
                          prefixIcon: Icon(Icons.two_wheeler),
                        ),
                        validator: validateModel,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('top-speed-field'),
                        controller: _topSpeed,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        style: AppText.body(18),
                        decoration: const InputDecoration(
                          labelText: 'Fastest possible speed',
                          suffixText: 'km/h',
                          prefixIcon: Icon(Icons.speed),
                          helperText:
                              'Manufacturer top speed or the fastest '
                              'your bike can go',
                        ),
                        validator: validateTopSpeed,
                        onFieldSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        key: const Key('save-bike'),
                        label: widget.editing ? 'SAVE' : 'CONTINUE',
                        icon: widget.editing
                            ? Icons.check
                            : Icons.arrow_forward_rounded,
                        busy: _saving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.red, Color(0xFFFF6B6B)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.two_wheeler, size: 46, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          'RIDEGUARD',
          style: AppText.display(32).copyWith(letterSpacing: 8),
        ),
      ],
    );
  }
}
