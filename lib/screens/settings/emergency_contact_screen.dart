import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'emergency_contact_card.dart';

/// Just the emergency contact, reached from the "No emergency contact"
/// warning.
class EmergencyContactScreen extends StatelessWidget {
  const EmergencyContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMERGENCY CONTACT')),
      body: const GradientBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: EmergencyContactCard(),
          ),
        ),
      ),
    );
  }
}
