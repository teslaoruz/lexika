import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: LexikaApp()));
}

class LexikaApp extends StatelessWidget {
  const LexikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lexika',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      home: const AppShell(),
    );
  }
}
