import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/api_client.dart';
import '../data/sync_service.dart';
import '../models/emergency_contact.dart';
import '../services/app_state.dart';
import '../services/emergency_platform.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/safety_overlay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(
    text: context.read<AppState>().apiUrl,
  );
  bool? _healthy;
  bool _checking = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _healthy = false);
      return;
    }
    setState(() => _checking = true);
    await context.read<AppState>().setApiUrl(_url.text);
    if (!mounted) return;
    final healthy = await context.read<ApiClient>().isHealthy();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _healthy = healthy;
    });
    if (healthy) await context.read<SyncService>().flush();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS')),
      body: GradientBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              SectionCard(
                title: 'BACKEND',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        helperText:
                            'Emulator: http://10.0.2.2:8000 · '
                            'Phone: http://<computer LAN IP>:8000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _saveAndTest,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('SAVE & TEST CONNECTION'),
                    ),
                    if (_healthy != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _healthy!
                            ? 'Connected - backend and database are up.'
                            : 'Could not reach a healthy backend at that URL.',
                        style: AppText.body(
                          14,
                          color: _healthy! ? AppColors.green : AppColors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _EmergencyContactCard(),
              const SizedBox(height: 12),
              const _SafetyLearningCard(),
              const SizedBox(height: 12),
              SectionCard(
                title: 'UPLOAD QUEUE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${sync.pending} requests waiting',
                      style: AppText.body(16),
                    ),
                    if (sync.lastSuccessAt != null)
                      Text(
                        'Last upload: ${sync.lastSuccessAt!.toLocal()}',
                        style: AppText.body(13, color: AppColors.textMuted),
                      ),
                    if (sync.lastError != null)
                      Text(
                        sync.lastError!,
                        style: AppText.body(13, color: AppColors.amber),
                      ),
                    if (sync.dropped > 0)
                      Text(
                        '${sync.dropped} rejected by the server',
                        style: AppText.body(13, color: AppColors.red),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: sync.pending == 0 ? null : sync.flush,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('RETRY NOW'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is called when a crash is not cancelled in time.
class _EmergencyContactCard extends StatefulWidget {
  const _EmergencyContactCard();

  @override
  State<_EmergencyContactCard> createState() => _EmergencyContactCardState();
}

class _EmergencyContactCardState extends State<_EmergencyContactCard> {
  final _form = GlobalKey<FormState>();
  late final EmergencyContact? _saved = context
      .read<AppState>()
      .emergencyContact;
  late final _name = TextEditingController(text: _saved?.name);
  late final _phone = TextEditingController(text: _saved?.phone);
  String? _status;
  bool _statusOk = true;
  bool _testing = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    final platform = context.read<EmergencyPlatform>();
    await app.setEmergencyContact(
      EmergencyContact(
        name: _name.text.trim(),
        phone: EmergencyContact.normalizePhone(_phone.text)!,
      ),
    );
    // Ask now: after a crash nobody can tap "Allow".
    final canCall = await platform.requestCallPermission();
    if (!mounted) return;
    setState(() {
      _statusOk = canCall;
      _status = canCall
          ? 'Saved. After a crash the app will call this number.'
          : 'Saved, but calling is not allowed: after a crash the dialer '
                'will only open with the number. Allow "Phone" for '
                'RideGuard in system settings.';
    });
  }

  Future<void> _remove() async {
    await context.read<AppState>().setEmergencyContact(null);
    _name.clear();
    _phone.clear();
    setState(() {
      _statusOk = false;
      _status = 'Removed. A crash will only sound the alarm.';
    });
  }

  Future<void> _testAlarm() async {
    final platform = context.read<EmergencyPlatform>();
    setState(() => _testing = true);
    await platform.startAlarm(urgent: true);
    await Future<void>.delayed(const Duration(seconds: 3));
    await platform.stopAlarm();
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasContact = context.watch<AppState>().emergencyContact != null;
    return SectionCard(
      title: 'EMERGENCY CONTACT',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'If a crash is detected, an alarm sounds and you get '
              '${AppConfig.crashCountdown.inSeconds} seconds to cancel. '
              'Then this number is called. Use a person, not 112/911: '
              'Android only opens the dialer for emergency numbers.',
              style: AppText.body(14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('contact-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('contact-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                helperText: 'Include the country code, e.g. +20 100 123 4567',
              ),
              validator: (v) => EmergencyContact.normalizePhone(v ?? '') == null
                  ? 'Enter a valid phone number'
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('save-contact'),
              onPressed: _save,
              icon: const Icon(Icons.contact_phone_outlined),
              label: const Text('SAVE CONTACT'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: AppText.body(
                  14,
                  color: _statusOk ? AppColors.green : AppColors.amber,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _testing ? null : () => unawaited(_testAlarm()),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('TEST ALARM'),
                  ),
                ),
                if (hasContact)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _remove,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('REMOVE'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What crash/wobble detection has learned about this mount.
class _SafetyLearningCard extends StatelessWidget {
  const _SafetyLearningCard();

  Future<void> _reset(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset safety learning?'),
        content: const Text(
          'Alerts go back to default sensitivity and the app learns again '
          'from your next rides. Do this after changing the phone mount.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (ok == true) await app.resetSafetyLearning();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SectionCard(
      title: 'SAFETY LEARNING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Every ride teaches the app how this bike and mount normally '
            'vibrate, so road buzz is not mistaken for a wobble. Learning '
            'only ever makes alerts less sensitive, never past a safe limit.',
            style: AppText.body(14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          SafetyLearningSummary(baseline: app.safetyBaseline),
          if (app.calibration != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('reset-safety-learning'),
              onPressed: () => _reset(context),
              icon: const Icon(Icons.restart_alt),
              label: const Text('RESET LEARNING'),
            ),
          ],
        ],
      ),
    );
  }
}
