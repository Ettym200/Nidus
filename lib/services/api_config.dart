import 'package:shared_preferences/shared_preferences.dart';
import 'translator_service.dart';

TranslatorService? translatorFromPrefs(SharedPreferences prefs) {
  final provider = prefs.getString('provider') ?? 'openai';
  final apiKey = prefs.getString('api_key_$provider') ?? '';
  if (apiKey.isEmpty) return null;
  return TranslatorService(
    apiKey: apiKey,
    provider: provider,
    model: prefs.getString('model') ?? '',
    targetLanguage: prefs.getString('language') ?? 'Português',
    customBaseUrl: prefs.getString('custom_base_url') ?? '',
  );
}

String? missingApiKeyMessage(SharedPreferences prefs) {
  final provider = prefs.getString('provider') ?? 'openai';
  final apiKey = prefs.getString('api_key_$provider') ?? '';
  if (apiKey.isEmpty) {
    return 'Configure a API Key em Configurações (⚙️)';
  }
  return null;
}
