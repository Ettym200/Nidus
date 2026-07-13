import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import '../services/api_config.dart';

/// Erros normais do STT do Android — não devem assustar o usuário.
bool _isSoftSttError(String msg) {
  final m = msg.toLowerCase();
  return m.contains('no_match') ||
      m.contains('error_no_match') ||
      m.contains('busy') ||
      m.contains('error_busy') ||
      m.contains('speech_timeout') ||
      m.contains('error_speech_timeout') ||
      m.contains('client') ||
      m.contains('error_client') ||
      m.contains('network_timeout') ||
      m.contains('timeout');
}

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
  bool _restartScheduled = false;
  Timer? _restartTimer;
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
        if (!_listening || !mounted) return;
        if (s == 'listening') {
          setState(() => _status = 'Ouvindo...');
        } else if (s == 'done' || s == 'notListening') {
          _scheduleRestart(delayMs: 1200);
        }
      },
      onError: (SpeechRecognitionError e) {
        if (!mounted || !_listening) return;
        // Erros “soft” são esperados em escuta contínua — só reinicia sem bip visual.
        if (_isSoftSttError(e.errorMsg)) {
          _scheduleRestart(delayMs: 1500);
          return;
        }
        setState(() => _status = 'Erro de áudio: ${e.errorMsg}');
        _scheduleRestart(delayMs: 2000);
      },
    );
    if (mounted) {
      setState(() =>
          _status = _available ? 'Pronto (microfone)' : 'STT indisponível neste aparelho');
    }
  }

  void _scheduleRestart({int delayMs = 1200}) {
    if (!_listening || _restartScheduled) return;
    _restartScheduled = true;
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: delayMs), () async {
      _restartScheduled = false;
      if (!_listening || !mounted) return;
      // Evita misturar restart com tradução / mic ocupado.
      if (_busy || _speech.isListening) {
        _scheduleRestart(delayMs: 800);
        return;
      }
      await _resumeListen();
    });
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
    try {
      await _speech.listen(
        localeId: _localeId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          enableHapticFeedback: false,
          autoPunctuation: true,
        ),
        onResult: (result) async {
          if (!mounted || !_listening) return;
          setState(() => _partial = result.recognizedWords);
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final spoken = result.recognizedWords.trim();
            setState(() => _partial = '');
            await _translateSpoken(spoken);
          }
        },
      );
    } catch (_) {
      _scheduleRestart(delayMs: 1500);
    }
  }

  Future<void> _translateSpoken(String spoken) async {
    if (_busy) return;
    // Filtra lixo / alucinações curtas demais
    if (spoken.length < 2) return;
    final t = translatorFromPrefs(widget.prefs);
    if (t == null) return;
    setState(() {
      _busy = true;
      _status = 'Traduzindo...';
    });
    try {
      final translated = await t.translateText(spoken, language: _lang);
      if (!mounted) return;
      if (translated.trim().isEmpty) return;
      setState(() {
        _history.insert(0, translated);
        if (_history.length > 8) _history.removeLast();
        _status = _listening ? 'Ouvindo...' : 'Parado';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro na API: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      // Continua ouvindo depois da tradução
      if (_listening) _scheduleRestart(delayMs: 400);
    }
  }

  Future<void> _stop() async {
    _listening = false;
    _restartTimer?.cancel();
    _restartScheduled = false;
    await _speech.stop();
    if (mounted) setState(() => _status = 'Parado');
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A2A4A)),
              ),
              child: const Text(
                'Usa o microfone do celular (STT do Android).\n'
                '• Se a live no mesmo celular pausar, baixe o volume dela ou '
                'solte o áudio em outro aparelho/caixa e deixe o Nidus ouvir.\n'
                '• Erros tipo “no match / busy / timeout” são normais e ficam ocultos.',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
              ),
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
