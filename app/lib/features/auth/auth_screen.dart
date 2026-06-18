import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

/// Sign-in / register gate. Email + password; register also picks a native
/// language (drives the translation extra). ponytail: one screen, a bool toggle
/// between the two modes — no router, no separate routes.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  String _lang = 'ru';
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final email = _email.text.trim();
    final pw = _password.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Enter an email and password');
      return;
    }
    if (_register && pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    final auth = ref.read(authControllerProvider.notifier);
    final name = _name.text.trim();
    try {
      if (_register) {
        await auth.register(email, pw, _lang,
            displayName: name.isEmpty ? null : name);
      } else {
        await auth.login(email, pw);
      }
      // On success the gate (LexikaApp) swaps to the app shell automatically.
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).loading;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              radius: 28,
              shadow: AppColors.shadowMd,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('📖 Lexika',
                      textAlign: TextAlign.center,
                      style: AppTheme.baloo(size: 30, weight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_register ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTheme.quick(
                          size: 15, color: AppColors.inkSoft)),
                  const SizedBox(height: 20),
                  _field(_email, 'Email', TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _field(_password, 'Password', TextInputType.text,
                      obscure: true),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    _field(_name, 'Name (shown on leaderboards)',
                        TextInputType.name),
                    const SizedBox(height: 12),
                    _langPicker(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: AppTheme.quick(
                            size: 13.5, color: AppColors.coralDark)),
                  ],
                  const SizedBox(height: 20),
                  AppButton(
                    label: loading
                        ? 'Please wait…'
                        : (_register ? 'Sign up' : 'Log in'),
                    onTap: loading ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              _register = !_register;
                              _error = null;
                            }),
                    child: Text(
                      _register
                          ? 'Have an account? Log in'
                          : "New here? Create an account",
                      style: AppTheme.quick(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: AppColors.violet),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Disclosure (TERMS.md / PRIVACY.md). ponytail: static text;
                  // wire tappable links to an in-app viewer when those screens exist.
                  Text(
                    'By continuing you agree to our Terms of Service & Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: AppTheme.quick(
                        size: 11.5, height: 1.4, color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, TextInputType type,
          {bool obscure = false}) =>
      TextField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        style: AppTheme.quick(size: 15),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: AppColors.bgSoft,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _langPicker() => Row(
        children: [
          Text('Native language',
              style: AppTheme.quick(size: 13.5, color: AppColors.inkSoft)),
          const Spacer(),
          DropdownButton<String>(
            value: _lang,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(14),
            style: AppTheme.quick(size: 14.5, color: AppColors.ink),
            items: const [
              DropdownMenuItem(value: 'ru', child: Text('Русский')),
              DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
            ],
            onChanged: (v) => setState(() => _lang = v ?? 'ru'),
          ),
        ],
      );
}
