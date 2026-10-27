import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/sync_service.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'account_card.dart';
import 'emergency_contact_card.dart';
import 'safety_learning_card.dart';

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
              const EmergencyContactCard(),
              const SizedBox(height: 12),
              const SafetyLearningCard(),
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
              const SizedBox(height: 12),
              const AccountCard(),
            ],
          ),
        ),
      ),
    );
  }
}
