import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

/// The sign-in screen: the learner picks an authentication method (phone,
/// Google, or email) and completes it. (Requirements 1.1–1.3)
///
/// The screen watches [authControllerProvider]: it shows progress while a
/// request is in flight, surfaces an error banner and stays put on failure
/// (Requirement 1.5), and lets FirebaseAuth's own auth-state stream drive the
/// router redirect on success. The AppBar title is the only "Sign in" text so
/// method labels read as "Continue with …" to keep the method choice clear.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

/// The method the learner is currently completing, or `null` at the top-level
/// method chooser.
enum _Method { phone, email }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  _Method? _method;

  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _chooseMethod(_Method? method) {
    ref.read(authControllerProvider.notifier).reset();
    setState(() => _method = method);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final busy = state is AuthInProgress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        leading: _method == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: busy ? null : () => _chooseMethod(null),
              ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state is AuthFailure) _ErrorBanner(message: state.message),
                  ..._buildBody(state, busy),
                  if (busy) ...const [
                    SizedBox(height: 24),
                    Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(AuthViewState state, bool busy) {
    switch (_method) {
      case null:
        return _buildMethodChooser(busy);
      case _Method.phone:
        return _buildPhoneForm(state, busy);
      case _Method.email:
        return _buildEmailForm(busy);
    }
  }

  List<Widget> _buildMethodChooser(bool busy) {
    final controller = ref.read(authControllerProvider.notifier);
    return [
      FilledButton.icon(
        onPressed: busy ? null : () => _chooseMethod(_Method.phone),
        icon: const Icon(Icons.phone),
        label: const Text('Continue with phone'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : controller.signInWithGoogle,
        icon: const Icon(Icons.account_circle),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : () => _chooseMethod(_Method.email),
        icon: const Icon(Icons.email),
        label: const Text('Continue with email'),
      ),
    ];
  }

  List<Widget> _buildPhoneForm(AuthViewState state, bool busy) {
    final controller = ref.read(authControllerProvider.notifier);

    if (state is AuthCodeSent) {
      final verificationId = state.verificationId;
      return [
        TextField(
          controller: _smsController,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Verification code',
            hintText: '123456',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () => controller.confirmPhoneCode(
                    verificationId: verificationId,
                    smsCode: _smsController.text.trim(),
                  ),
          child: const Text('Verify code'),
        ),
      ];
    }

    return [
      TextField(
        controller: _phoneController,
        enabled: !busy,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+1 555 123 4567',
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy
            ? null
            : () => controller.startPhoneSignIn(_phoneController.text.trim()),
        child: const Text('Send code'),
      ),
    ];
  }

  List<Widget> _buildEmailForm(bool busy) {
    final controller = ref.read(authControllerProvider.notifier);
    return [
      TextField(
        controller: _emailController,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        enabled: !busy,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy
            ? null
            : () => controller.signInWithEmail(
                  email: _emailController.text.trim(),
                  password: _passwordController.text,
                ),
        child: const Text('Log in'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: busy
            ? null
            : () => controller.registerWithEmail(
                  email: _emailController.text.trim(),
                  password: _passwordController.text,
                ),
        child: const Text('Create account'),
      ),
    ];
  }
}

/// A prominent, accessible error banner shown above the sign-in form when a
/// request fails, keeping the learner on the screen. (Requirement 1.5)
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
