import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import '../services/api_config.dart';

bool _isSoftSttError(String msg) {
  final m = msg.toLowerCase();
  return m.contains('no_match') ||
      m.contains('busy') ||
      m.contains('speech_timeout') ||
      m.contains('timeout') ||
      m.contains('error_client') ||
      m.contains('client');
}

class InterviewScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const InterviewScreen({super.key, required this.prefs});

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final _contextCtrl = TextEditingController();
  final _buffer = StringBuffer();
  DateTime? _lastSpeechAt;
  String _question = '';
  String _answer = '';
  String _partial = '';
  String _status = 'Parado';
  String _interviewType = 'Geral';
  String _answerLang = 'Português';
  bool _running = false;
  bool _busy = false;
  bool _available = false;
  bool _restartScheduled = false;
  Timer? _restartTimer;

  static const _types = ['Geral', 'Técnica', 'Comportamental', 'RH / Cultura'];
  static const _languages = [
    'Português', 'English', 'Español', 'Français', 'Deutsch', '日本語', '한국어', '中文',
  ];

  @override
  void initState() {
    super.initState();
    _contextCtrl.text = widget.prefs.getString('interview_context') ?? '';
    _interviewType = widget.prefs.getString('interview_type') ?? 'Geral';
    _answerLang = widget.prefs.getString('interview_answer_language') ??
        widget.prefs.getString('language') ??
        'Português';
    _initSpeech();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _speech.stop();
    _contextCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _status = 'Permissão de microfone negada');
      return;
    }
    _available = await _speech.initialize(
      onStatus: (s) {
        if (!_running || !mounted) return;
        if (s == 'done' || s == 'notListening') {
          _scheduleRestart(delayMs: 1200);
        }
      },
      onError: (SpeechRecognitionError e) {
        if (!_running || !mounted) return;
        if (_isSoftSttError(e.errorMsg)) {
          _scheduleRestart(delayMs: 1500);
          return;
        }
        setState(() => _status = 'Erro de áudio: ${e.errorMsg}');
        _scheduleRestart(delayMs: 2000);
      },
    );
    if (mounted && _available) setState(() => _status = 'Pronto');
  }

  void _scheduleRestart({int delayMs = 1200}) {
    if (!_running || _restartScheduled) return;
    _restartScheduled = true;
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: delayMs), () async {
      _restartScheduled = false;
      if (!_running || !mounted) return;
      if (_busy || _speech.isListening) {
        _scheduleRestart(delayMs: 800);
        return;
      }
      await _resumeListen();
    });
  }

  String get _localeId {
    switch (_answerLang) {
      case 'English':
        return 'en_US';
      case 'Español':
        return 'es_ES';
      default:
        return 'pt_BR';
    }
  }

  Future<void> _toggle() async {
    if (_running) {
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
    widget.prefs.setString('interview_context', _contextCtrl.text.trim());
    widget.prefs.setString('interview_type', _interviewType);
    widget.prefs.setString('interview_answer_language', _answerLang);
    setState(() {
      _running = true;
      _status = 'Ouvindo entrevistador...';
      _buffer.clear();
    });
    await _resumeListen();
  }

  Future<void> _resumeListen() async {
    if (!_running || !mounted) return;
    try {
      await _speech.listen(
        localeId: _localeId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          enableHapticFeedback: false,
          autoPunctuation: true,
        ),
        onResult: (result) async {
          if (!mounted || !_running) return;
          setState(() {
            _partial = result.recognizedWords;
            _lastSpeechAt = DateTime.now();
          });
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final chunk = result.recognizedWords.trim();
            if (_buffer.isNotEmpty) _buffer.write(' ');
            _buffer.write(chunk);
            setState(() {
              _question = _buffer.toString();
              _partial = '';
            });
            await Future.delayed(const Duration(milliseconds: 1000));
            final quiet = _lastSpeechAt == null ||
                DateTime.now().difference(_lastSpeechAt!) >
                    const Duration(milliseconds: 1800);
            if (quiet && _buffer.isNotEmpty && !_busy) {
              final full = _buffer.toString();
              _buffer.clear();
              await _suggest(full);
            }
          }
        },
      );
    } catch (_) {
      _scheduleRestart(delayMs: 1500);
    }
  }

  Future<void> _suggest(String question) async {
    final t = translatorFromPrefs(widget.prefs);
    if (t == null) return;
    setState(() {
      _busy = true;
      _question = question;
      _status = 'Gerando resposta...';
    });
    try {
      final answer = await t.suggestInterviewAnswer(
        question: question,
        answerLanguage: _answerLang,
        context: _contextCtrl.text,
        interviewType: _interviewType,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _status = _running ? 'Ouvindo...' : 'Parado';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (_running) _scheduleRestart(delayMs: 400);
    }
  }

  Future<void> _stop() async {
    _running = false;
    _restartTimer?.cancel();
    _restartScheduled = false;
    await _speech.stop();
    if (mounted) setState(() => _status = 'Parado');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Entrevista', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ouve o entrevistador pelo microfone e sugere respostas com base no seu perfil.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const Text('Seu perfil', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _contextCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cargo, stack, experiência...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF16213E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _interviewType,
                  dropdownColor: const Color(0xFF16213E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: _running ? null : (v) => setState(() => _interviewType = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _answerLang,
                  dropdownColor: const Color(0xFF16213E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Respostas em',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: _running ? null : (v) => setState(() => _answerLang = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggle,
            icon: Icon(_running ? Icons.stop : Icons.hearing),
            label: Text(_running ? 'Parar entrevista' : 'Iniciar modo entrevista'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _running ? Colors.red : const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (_partial.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_partial, style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          const Text('Pergunta', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _question.isEmpty ? '—' : _question,
                style: TextStyle(color: _question.isEmpty ? Colors.white38 : Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Sugestão', style: TextStyle(color: Color(0xFF03DAC6), fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  if (_answer.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: _answer));
                  setState(() => _status = 'Resposta copiada!');
                },
                icon: const Icon(Icons.copy, size: 16, color: Color(0xFF03DAC6)),
                label: const Text('Copiar', style: TextStyle(color: Color(0xFF03DAC6))),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0E17),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A2A4A)),
              ),
              child: Text(
                _answer.isEmpty ? '—' : _answer,
                style: TextStyle(
                  color: _answer.isEmpty ? Colors.white38 : const Color(0xFF03DAC6),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
