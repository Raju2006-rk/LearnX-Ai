import 'package:flutter/material.dart';

/// Placeholder for the Account destination of the navigation shell.
///
/// The real account content (profile, settings, sign-out) lands in later
/// tasks (10.x). This keeps the Account branch renderable so the shell can
/// boot. (Requirements 12.1, 12.2)
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: const Center(child: Text('Account')),
    );
  }
}
