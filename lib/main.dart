import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(GameTranslatorApp(prefs: prefs));
}

class GameTranslatorApp extends StatelessWidget {
  final SharedPreferences prefs;
  const GameTranslatorApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nidus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        cardColor: const Color(0xFF16213E),
      ),
      home: HomeScreen(prefs: prefs),
    );
  }
}
