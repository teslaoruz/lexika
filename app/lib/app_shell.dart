import 'package:flutter/material.dart';

import 'features/decks/decks_screen.dart';
import 'features/lookup/lookup_screen.dart';
import 'features/progress/progress_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/fade_up.dart';
import 'widgets/mode_tabs.dart';
import 'widgets/top_bar.dart';

/// App frame: top bar + sliding-pill mode tabs + screen + bottom nav, all kept
/// in sync via a single [_index] (prototype's tab/nav sync behavior).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [
    LookupScreen(),
    DecksScreen(),
    ProgressScreen(),
  ];

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        // Phone-width frame like the prototype's 480px app-frame.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SafeArea(
            child: Column(
              children: [
                const TopBar(),
                ModeTabs(index: _index, onChanged: _select),
                Expanded(
                  child: FadeUp(
                    key: ValueKey(_index),
                    child: _screens[_index],
                  ),
                ),
                BottomNav(index: _index, onChanged: _select),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
