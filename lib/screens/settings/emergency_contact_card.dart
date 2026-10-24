import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/emergency_contact.dart';
import '../../services/app_state.dart';
import '../../services/emergency_platform.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Who is called when a crash is not cancelled in time.
class EmergencyContactCard extends StatefulWidget {
  const EmergencyContactCard({super.key});

  @override
  State<EmergencyContactCard> createState() => EmergencyContactCardState();
}

class EmergencyContactCardState extends State<EmergencyContactCard> {
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
