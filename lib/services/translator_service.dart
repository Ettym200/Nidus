import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const _systemPrompt =
    'Esta é uma captura de tela de um jogo. '
    'Extraia APENAS o texto de legenda ou diálogo visível (ignore HUD, números, nomes de missão, ícones). '
    'Traduza esse texto para {lang}. '
    'Responda SOMENTE com a tradução, sem explicações. '
    'Se não houver legenda ou diálogo, responda com uma string vazia.';

class TranslatorService {
  final String apiKey;
  final String provider;
  final String model;
  final String targetLanguage;
  final String customBaseUrl;

  TranslatorService({
    required this.apiKey,
    required this.provider,
    required this.model,
    required this.targetLanguage,
    this.customBaseUrl = '',
  });

  String get _baseUrl {
    switch (provider) {
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'custom':
        return customBaseUrl;
      default:
        return 'https://api.openai.com/v1';
    }
  }

  String get _defaultModel {
    switch (provider) {
      case 'openrouter':
        return 'openai/gpt-4o-mini';
      case 'groq':
        return 'meta-llama/llama-4-scout-17b-16e-instruct';
      case 'anthropic':
        return 'claude-haiku-4-5-20251001';
      default:
        return 'gpt-4o-mini';
    }
  }

  String get _model => model.isNotEmpty ? model : _defaultModel;

  Future<String> translate(Uint8List imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final prompt = _systemPrompt.replaceAll('{lang}', targetLanguage);

    if (provider == 'anthropic') {
      return _translateAnthropic(b64, prompt);
    } else {
      return _translateOpenAICompat(b64, prompt);
    }
  }

  Future<String> _translateOpenAICompat(String b64, String prompt) async {
    final url = Uri.parse('$_baseUrl/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 300,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$b64'},
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Erro ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return (data['choices'][0]['message']['content'] as String? ?? '').trim();
  }

  Future<String> _translateAnthropic(String b64, String prompt) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    final response = await http.post(
      url,
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 300,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': b64,
                },
              },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Erro ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return (data['content'][0]['text'] as String? ?? '').trim();
  }
}
