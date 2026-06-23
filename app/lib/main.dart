import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/providers.dart';
import 'app_shell.dart';
import 'features/auth/auth_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/app_button.dart';

void main() {
  runApp(const ProviderScope(child: LexikaApp()));
}

class LexikaApp extends ConsumerWidget {
  const LexikaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Apply dark mode before any widget reads the AppColors getters this build.
    AppColors.dark = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Lexika',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      // Wait for the backend to be reachable before the auth flow runs — the
      // free-tier host sleeps when idle and a cold start can take ~a minute.
      home: const ServerGate(child: _AppRoot()),
    );
  }
}

/// Auth gate: while restoring a saved session → splash; then app shell or sign-in.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    // Only the initial session-restore shows the splash. An in-flight login
    // keeps AuthScreen mounted so its spinner + error banner can render.
    if (auth.initializing) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(child: Text('📖', style: TextStyle(fontSize: 48))),
      );
    }
    return auth.signedIn ? const AppShell() : const AuthScreen();
  }
}

/// Probes `/health` on launch and shows a "waking up" screen until the backend
/// answers, so a sleeping free-tier server reads as "starting…" rather than a
/// silent failure. Renders [child] only once the server is reachable.
class ServerGate extends ConsumerStatefulWidget {
  const ServerGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ServerGate> createState() => _ServerGateState();
}

enum _Status { checking, ready, down }

class _ServerGateState extends ConsumerState<ServerGate> {
  _Status _status = _Status.checking;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    if (mounted) setState(() => _status = _Status.checking);
    final api = ref.read(apiClientProvider);
    // Each ping waits up to ~35s (cold start), retried a few times. Normally the
    // first ping returns in well under a second when the server is already warm.
    for (var attempt = 0; attempt < 6; attempt++) {
      if (await api.ping()) {
        if (mounted) setState(() => _status = _Status.ready);
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) setState(() => _status = _Status.down);
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _Status.ready:
        return widget.child;
      case _Status.checking:
        return _Splash(
          emoji: '☕',
          title: 'Getting things ready…',
          subtitle: 'This will only take a few seconds. Hang tight.',
          showSpinner: true,
        );
      case _Status.down:
        return _Splash(
          emoji: '😴',
          title: "Can't reach the server",
          subtitle:
              'It may be starting up or temporarily offline. Check your '
              'connection and try again.',
          onRetry: _probe,
        );
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.showSpinner = false,
    this.onRetry,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool showSpinner;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTheme.baloo(size: 20, weight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(
                      size: 14, height: 1.5, color: AppColors.inkFaint)),
              const SizedBox(height: 24),
              if (showSpinner)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: AppColors.violet),
                ),
              if (onRetry != null)
                AppButton(
                  label: 'Try again',
                  bg: AppColors.violet,
                  shadow: AppColors.shadowViolet,
                  expand: false,
                  onTap: onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
