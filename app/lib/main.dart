import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/providers.dart';
import 'app_shell.dart';
import 'features/auth/auth_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: LexikaApp()));
}

class LexikaApp extends ConsumerWidget {
  const LexikaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate: while restoring a saved session → splash; then app shell or sign-in.
    final auth = ref.watch(authControllerProvider);
    // Only the initial session-restore shows the splash. An in-flight login
    // keeps AuthScreen mounted so its spinner + error banner can render.
    final Widget home = auth.initializing
        ? const Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(child: Text('📖', style: TextStyle(fontSize: 48))),
          )
        : (auth.signedIn ? const AppShell() : const AuthScreen());
    return MaterialApp(
      title: 'Lexika',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      home: home,
    );
  }
}
