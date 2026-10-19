import 'package:flutter/material.dart';

/// Placeholder for the Premium destination shown in navigation for the MVP.
///
/// Billing and premium entitlements are deferred; per Requirement 12.3 the
/// Premium destination is presented as a placeholder screen in the MVP.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: const Center(child: Text('Premium coming soon')),
    );
  }
}
