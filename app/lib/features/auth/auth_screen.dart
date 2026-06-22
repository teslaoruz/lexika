import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';

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
      // On success the gate (LexikaApp) swaps to the app shell. Flash a quick
      // confirmation first so the tap clearly registered.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_register ? 'Account created 🎉' : 'Welcome back 👋',
              style: AppTheme.baloo(
                  size: 14.5, weight: FontWeight.w700, color: AppColors.white)),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.mintDark,
        ));
    } on ApiException catch (e) {
      // Wrong credentials: clear the password so the user retypes it cleanly.
      _password.clear();
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // Defensive: never fail silently, even on an unexpected error type.
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
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
                  Text(
                      _register
                          ? 'Build a vocabulary that sticks'
                          : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTheme.quick(
                          size: 15, color: AppColors.inkSoft)),
                  const SizedBox(height: 20),
                  _field(_email, 'Email', TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _field(_password, 'Password', TextInputType.text,
                      obscure: true),
                  if (_register) ...[
                    const SizedBox(height: 6),
                    Text('At least 8 characters',
                        style: AppTheme.quick(
                            size: 12, color: AppColors.inkFaint)),
                    const SizedBox(height: 12),
                    _field(_name, 'Name (shown on leaderboards)',
                        TextInputType.name),
                    const SizedBox(height: 16),
                    _langPicker(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    // Filled banner, not thin text — an auth error must be
                    // impossible to miss.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.coralLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 18, color: AppColors.coralDark),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: AppTheme.quick(
                                    size: 13.5,
                                    weight: FontWeight.w600,
                                    height: 1.35,
                                    color: AppColors.coralDark)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Spinner overlays the button while a request is in flight so
                  // the tap visibly registers (the old "Please wait…" label gave
                  // no motion feedback).
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: loading ? 0.6 : 1,
                        child: AppButton(
                          label: loading
                              ? ''
                              : (_register ? 'Sign up' : 'Log in'),
                          onTap: loading ? null : _submit,
                        ),
                      ),
                      if (loading)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: AppColors.white),
                        ),
                    ],
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

  // Branded segmented picker instead of a bare grey Material dropdown — tap a
  // pill, no menu. Translations use this language.
  Widget _langPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('I speak',
              style: AppTheme.quick(size: 13.5, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _langChip('ru', 'Русский'),
            _langChip('kk', 'Қазақша'),
            _langChip('fa', 'فارسی'),
          ]),
        ],
      );

  Widget _langChip(String value, String label) {
    final selected = _lang == value;
    return AppChip(
      label: label,
      useBaloo: true,
      bg: selected ? AppColors.violet : AppColors.bgSoft,
      fg: selected ? AppColors.white : AppColors.inkSoft,
      onTap: () => setState(() => _lang = value),
    );
  }
}
