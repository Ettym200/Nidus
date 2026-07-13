import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_config.dart';

class TextTranslateScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const TextTranslateScreen({super.key, required this.prefs});

  @override
  State<TextTranslateScreen> createState() => _TextTranslateScreenState();
}

class _TextTranslateScreenState extends State<TextTranslateScreen> {
  final _input = TextEditingController();
  String _output = '';
  String _status = '';
  bool _busy = false;
  late String _lang;

  static const _languages = [
    'Português', 'English', 'Español', 'Français', 'Deutsch', '日本語', '한국어', '中文',
  ];

  @override
  void initState() {
    super.initState();
    _lang = widget.prefs.getString('language') ?? 'Português';
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final msg = missingApiKeyMessage(widget.prefs);
    if (msg != null) {
      setState(() => _status = msg);
      return;
    }
    final t = translatorFromPrefs(widget.prefs)!;
    setState(() {
      _busy = true;
      _status = 'Traduzindo...';
    });
    try {
      final result = await t.translateText(text, language: _lang);
      setState(() {
        _output = result;
        _status = 'Concluído';
      });
    } catch (e) {
      setState(() {
        _output = 'Erro: $e';
        _status = 'Erro';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (_output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output));
    setState(() => _status = 'Copiado!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Traduzir Texto', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Para:', style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _lang,
                    dropdownColor: const Color(0xFF16213E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _languages
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(() => _lang = v!),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _translate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_busy ? '...' : 'Traduzir'),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Cole o texto aqui...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF16213E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Tradução', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy, size: 16, color: Color(0xFF03DAC6)),
                  label: const Text('Copiar', style: TextStyle(color: Color(0xFF03DAC6))),
                ),
              ],
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A4A)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _output.isEmpty ? '—' : _output,
                    style: TextStyle(
                      color: _output.isEmpty ? Colors.white38 : const Color(0xFF03DAC6),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
