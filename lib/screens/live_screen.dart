import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_config.dart';

/// Live por áudio INTERNO (não pausa a live) + Whisper + tradução.
class LiveScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const LiveScreen({super.key, required this.prefs});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const _channel = MethodChannel('game_translator/overlay');
  static const _events = EventChannel('game_translator/live_audio');

  final List<String> _history = [];
  String _status = 'Parado';
  String _partial = '';
  bool _listening = false;
  bool _busy = false;
  StreamSubscription? _sub;
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
    _sub?.cancel();
    if (_listening) {
      _channel.invokeMethod('stopLiveAudio');
    }
    super.dispose();
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
    final t = translatorFromPrefs(widget.prefs);
    if (t == null) return;
    if (!t.supportsWhisper) {
      setState(() => _status =
          'Live interno precisa de OpenAI, Groq ou OpenRouter (Anthropic não tem Whisper).');
      return;
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _status = 'Permissão de microfone necessária (Android exige mesmo em captura interna)');
      return;
    }

    setState(() {
      _status = 'Autorize a captura de tela/áudio...';
    });

    try {
      await _sub?.cancel();
      _sub = _events.receiveBroadcastStream().listen((event) {
        if (event is! Map) return;
        final type = event['type']?.toString();
        if (type == 'status') {
          if (mounted) setState(() => _status = event['message']?.toString() ?? _status);
        } else if (type == 'chunk') {
          final path = event['path']?.toString();
          if (path != null) _onChunk(path);
        }
      });

      await _channel.invokeMethod('startLiveAudio');
      setState(() {
        _listening = true;
        _status = 'Capturando áudio interno...';
      });
    } catch (e) {
      setState(() => _status = 'Erro: $e');
      await _sub?.cancel();
      _sub = null;
    }
  }

  Future<void> _onChunk(String path) async {
    if (_busy || !_listening) {
      try { File(path).deleteSync(); } catch (_) {}
      return;
    }
    final t = translatorFromPrefs(widget.prefs);
    if (t == null) return;

    setState(() {
      _busy = true;
      _status = 'Transcrevendo...';
    });
    try {
      final bytes = await File(path).readAsBytes();
      try { File(path).deleteSync(); } catch (_) {}

      final spoken = await t.transcribeWav(bytes);
      if (!mounted || !_listening) return;
      if (spoken.trim().length < 2) {
        setState(() => _status = 'Capturando áudio interno...');
        return;
      }
      setState(() {
        _partial = spoken;
        _status = 'Traduzindo...';
      });
      final translated = await t.translateText(spoken, language: _lang);
      if (!mounted || !_listening) return;
      if (translated.trim().isEmpty) return;
      setState(() {
        _history.insert(0, translated);
        if (_history.length > 10) _history.removeLast();
        _partial = '';
        _status = 'Capturando áudio interno...';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _listening = false);
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel.invokeMethod('stopLiveAudio');
    } catch (_) {}
    setState(() {
      _status = 'Parado';
      _partial = '';
    });
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
                border: Border.all(color: const Color(0xFF03DAC6), width: 1),
              ),
              child: const Text(
                'Agora captura o áudio INTERNO da tela (Android 10+) — '
                'não usa o microfone para escutar a live, então não deve mais pausar o vídeo.\n\n'
                'Ao iniciar, aceite a permissão de captura. '
                'Use OpenAI, Groq ou OpenRouter (Whisper).',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
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
              icon: Icon(_listening ? Icons.stop : Icons.graphic_eq),
              label: Text(_listening ? 'Parar Live' : 'Iniciar Live (áudio interno)'),
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
                style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 12),
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
