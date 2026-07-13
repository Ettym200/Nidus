import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'interview_screen.dart';
import 'text_translate_screen.dart';
import 'uga_buga_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  final SharedPreferences prefs;
  const MainShell({super.key, required this.prefs});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(prefs: widget.prefs),
      LiveScreen(prefs: widget.prefs),
      InterviewScreen(prefs: widget.prefs),
      TextTranslateScreen(prefs: widget.prefs),
      UgaBugaScreen(prefs: widget.prefs),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF16213E),
        indicatorColor: const Color(0xFF6C63FF).withOpacity(0.35),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Jogo'),
          NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.record_voice_over_outlined), selectedIcon: Icon(Icons.record_voice_over), label: 'Entrevista'),
          NavigationDestination(icon: Icon(Icons.translate), selectedIcon: Icon(Icons.translate), label: 'Texto'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Uga'),
        ],
      ),
      floatingActionButton: _index == 0
          ? null
          : FloatingActionButton.small(
              backgroundColor: const Color(0xFF16213E),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsScreen(prefs: widget.prefs)),
                );
              },
              child: const Icon(Icons.settings, color: Colors.white),
            ),
    );
  }
}
