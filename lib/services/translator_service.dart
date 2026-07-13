import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const _systemPrompt =
    'Esta é uma captura de tela de um jogo. '
    'Extraia APENAS o texto de legenda ou diálogo visível (ignore HUD, números, nomes de missão, ícones). '
    'Traduza esse texto para {lang}. '
    'Responda SOMENTE com a tradução, sem explicações. '
    'Se não houver legenda ou diálogo, responda com uma string vazia.';

const _ugaBugaPrompt =
    'Resuma o item, skill, talento ou equipamento de jogo no estilo "uga buga" '
    '(meme brasileiro: linguagem pré-histórica simplificada e engraçada).\n\n'
    'Exemplos de tom (varie o estilo, não repita a mesma fórmula):\n'
    '- bater forte, inimigo cai\n'
    '- dano grandão, muito feliz\n'
    '- dano grandão = homem feliz\n'
    '- magia gelo congelá bicho, dano extra se já frio\n'
    '- escudo grandão, inimigo bate e vc quase nem sente\n'
    '- cooldown 8s, dá pra spammar na briga\n\n'
    'Regras:\n'
    '- Português informal, frases curtas, tom de caverna engraçado\n'
    '- Use "= homem feliz", "muito feliz" ou "vc feliz" NO MÁXIMO 1 vez no resumo inteiro '
    '(só na parte mais importante/benefício principal — não em todo tópico)\n'
    '- A maioria das frases deve descrever o efeito direto, sem falar de felicidade\n'
    '- 2 a 5 frases OU 3 a 6 tópicos com •\n'
    '- Explique o que faz de verdade, mas ultra simplificado\n'
    '- Pode mencionar detalhes menores (cooldown, stack, %, condição) em uga buga\n'
    '- Não repita a mesma ideia em bullets e parágrafos — resuma uma vez só\n'
    '- Sem introdução, sem "aqui está", sem aspas no começo\n';

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
      return _visionAnthropic([b64], prompt, maxTokens: 300);
    }
    return _visionOpenAICompat([b64], prompt, maxTokens: 300);
  }

  Future<String> translateText(String text, {String? language}) async {
    final lang = language ?? targetLanguage;
    final prompt =
        'Traduza o texto a seguir para $lang. Responda SOMENTE com a tradução, sem explicações:\n\n$text';
    return _textChat(prompt, maxTokens: 2000);
  }

  Future<String> summarizeUgaBuga({
    String text = '',
    List<Uint8List> images = const [],
  }) async {
    final extra = text.trim();
    if (images.isNotEmpty) {
      var prompt = _ugaBugaPrompt;
      if (extra.isNotEmpty) {
        prompt += '\nTexto extra fornecido pelo usuário:\n$extra\n';
      }
      if (images.length > 1) {
        prompt +=
            '\nSão ${images.length} imagens — leia todas (nome, descrição, stats) '
            'e faça um resumo uga buga combinado.';
      } else {
        prompt +=
            '\nLeia todo o texto visível na imagem (nome, descrição, stats) e resuma.';
      }
      final b64List = images.map(base64Encode).toList();
      if (provider == 'anthropic') {
        return _visionAnthropic(b64List, prompt, maxTokens: 800);
      }
      return _visionOpenAICompat(b64List, prompt, maxTokens: 800);
    }

    if (extra.isEmpty) {
      throw Exception('Informe texto ou imagem do item/skill.');
    }
    return _textChat(
      '$_ugaBugaPrompt\n\nTexto do item/skill:\n$extra',
      maxTokens: 800,
    );
  }

  Future<String> suggestInterviewAnswer({
    required String question,
    required String answerLanguage,
    String context = '',
    String interviewType = 'Geral',
  }) async {
    final ctx = context.trim().isEmpty
        ? '(Nenhum contexto fornecido — responda de forma genérica e profissional.)'
        : context.trim();
    final prompt =
        'You are an expert interview coach helping a candidate respond live.\n\n'
        'Candidate context:\n$ctx\n\n'
        'Interview type: $interviewType\n'
        'The interviewer said (full statement, may include multiple sentences):\n"$question"\n\n'
        'Write the best answer the candidate should say aloud, in $answerLanguage.\n'
        'Rules:\n'
        '- Read the ENTIRE statement before answering — it may be a long or multi-part question\n'
        '- Sound natural and spoken (not a written essay)\n'
        '- Be professional, confident, and concise\n'
        '- Address all parts of the question if there are several\n'
        '- Prefer 2–6 sentences unless the question needs more detail\n'
        '- Do not invent specific facts not supported by the context\n'
        '- Respond ONLY with the suggested answer — no labels, quotes, or explanations';
    return _textChat(prompt, maxTokens: 2000);
  }

  /// Whisper (OpenAI / Groq / OpenRouter). Anthropic não tem STT.
  String get whisperModel {
    switch (provider) {
      case 'groq':
        return 'whisper-large-v3';
      case 'openrouter':
        return 'openai/whisper-1';
      default:
        return 'whisper-1';
    }
  }

  bool get supportsWhisper => provider != 'anthropic';

  Future<String> transcribeWav(Uint8List wavBytes, {String language = 'auto'}) async {
    if (!supportsWhisper) {
      throw Exception(
        'Provedor Anthropic não tem Whisper. Use OpenAI, Groq ou OpenRouter no Live.',
      );
    }
    final uri = Uri.parse('$_baseUrl/audio/transcriptions');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $apiKey';
    req.fields['model'] = whisperModel;
    if (language != 'auto' && language.isNotEmpty) {
      // códigos curtos quando possível
      final code = switch (language) {
        'Português' => 'pt',
        'English' => 'en',
        'Español' => 'es',
        'Français' => 'fr',
        'Deutsch' => 'de',
        '日本語' => 'ja',
        '한국어' => 'ko',
        '中文' => 'zh',
        _ => '',
      };
      if (code.isNotEmpty) req.fields['language'] = code;
    }
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      wavBytes,
      filename: 'audio.wav',
    ));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Whisper ${streamed.statusCode}: $body');
    }
    final data = jsonDecode(body);
    return (data['text'] as String? ?? '').trim();
  }

  Future<String> _textChat(String prompt, {int maxTokens = 1000}) async {
    if (provider == 'anthropic') {
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
          'max_tokens': maxTokens,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Erro ${response.statusCode}: ${response.body}');
      }
      final data = jsonDecode(response.body);
      return _clean((data['content'][0]['text'] as String? ?? '').trim());
    }

    final url = Uri.parse('$_baseUrl/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Erro ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return _clean(
      (data['choices'][0]['message']['content'] as String? ?? '').trim(),
    );
  }

  Future<String> _visionOpenAICompat(
    List<String> b64List,
    String prompt, {
    int maxTokens = 300,
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
      for (final b64 in b64List)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$b64'},
        },
    ];
    final url = Uri.parse('$_baseUrl/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': content},
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Erro ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return _clean(
      (data['choices'][0]['message']['content'] as String? ?? '').trim(),
    );
  }

  Future<String> _visionAnthropic(
    List<String> b64List,
    String prompt, {
    int maxTokens = 300,
  }) async {
    final content = <Map<String, dynamic>>[
      for (final b64 in b64List)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': b64,
          },
        },
      {'type': 'text', 'text': prompt},
    ];
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
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': content},
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Erro ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return _clean((data['content'][0]['text'] as String? ?? '').trim());
  }

  String _clean(String text) {
    return text
        .replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '')
        .replaceAll('```', '')
        .trim();
  }
}
