import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/api_config.dart';

class LiveScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const LiveScreen({super.key, required this.prefs});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final List<String> _history = [];
  String _partial = '';
  String _status = 'Parado';
  bool _listening = false;
  bool _busy = false;
  bool _available = false;
  late String _lang;

  static const _languages = [
    'Português', 'English', 'Español', 'Français', 'Deutsch', '日本語', '한국어', '中文',
  ];

  @override
  void initState() {
    super.initState();
    _lang = widget.prefs.getString('language') ?? 'Português';
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _status = 'Permissão de microfone negada');
      return;
    }
    _available = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (_listening && mounted) {
            // Reinicia escuta contínua
            Future.delayed(const Duration(milliseconds: 300), _resumeListen);
          }
        }
      },
      onError: (e) {
        if (mounted) setState(() => _status = 'STT: ${e.errorMsg}');
      },
    );
    if (mounted) {
      setState(() => _status = _available ? 'Pronto (microfone)' : 'STT indisponível neste aparelho');
    }
  }

  String get _localeId {
    switch (_lang) {
      case 'English':
        return 'en_US';
      case 'Español':
        return 'es_ES';
      case 'Français':
        return 'fr_FR';
      case 'Deutsch':
        return 'de_DE';
      case '日本語':
        return 'ja_JP';
      case '한국어':
        return 'ko_KR';
      case '中文':
        return 'zh_CN';
      default:
        return 'pt_BR';
    }
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stop();
      return;
    }
    final msg = missingApiKeyMessage(widget.prefs);
    if (msg != null) {
      setState(() => _status = msg);
      return;
    }
    if (!_available) {
      await _initSpeech();
      if (!_available) return;
    }
    setState(() {
      _listening = true;
      _status = 'Ouvindo...';
    });
    await _resumeListen();
  }

  Future<void> _resumeListen() async {
    if (!_listening || !mounted) return;
    await _speech.listen(
      localeId: _localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      onResult: (result) async {
        if (!mounted) return;
        setState(() => _partial = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          final spoken = result.recognizedWords.trim();
          setState(() => _partial = '');
          await _translateSpoken(spoken);
        }
      },
    );
  }

  Future<void> _translateSpoken(String spoken) async {
    if (_busy) return;
    final t = translatorFromPrefs(widget.prefs);
    if (t == null) return;
    setState(() {
      _busy = true;
      _status = 'Traduzindo...';
    });
    try {
      final translated = await t.translateText(spoken, language: _lang);
      if (!mounted) return;
      setState(() {
        _history.insert(0, translated);
        if (_history.length > 8) _history.removeLast();
        _status = _listening ? 'Ouvindo...' : 'Parado';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _listening = false);
    await _speech.stop();
    setState(() => _status = 'Parado');
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Live', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Captura áudio pelo microfone, reconhece a fala e traduz em tempo real. '
              'Aproxime o celular do áudio da live/vídeo.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Traduzir para:', style: TextStyle(color: Colors.white70)),
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
                    onChanged: _listening ? null : (v) => setState(() => _lang = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _toggle,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'Parar Live' : 'Iniciar Live'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _listening ? Colors.red : const Color(0xFFE94560),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (_partial.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _partial,
                style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Traduções', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text('Nada ainda', style: TextStyle(color: Colors.white38)))
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _history[i],
                                style: const TextStyle(color: Color(0xFF03DAC6), fontSize: 15),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18, color: Colors.white54),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _history[i]));
                                setState(() => _status = 'Copiado!');
                              },
                            ),
                          ],
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
