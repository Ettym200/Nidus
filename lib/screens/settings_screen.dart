import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _providers = ['openai', 'anthropic', 'openrouter', 'groq', 'custom'];
const _languages = ['Português', 'English', 'Español', 'Français', 'Deutsch', '日本語', '한국어', '中文'];
const _overlayStyles = {
  'transparent': 'Transparente',
  'semi': 'Semi-transparente',
  'dark': 'Escuro',
  'black': 'Preto',
  'blue': 'Azul escuro',
};

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsScreen({super.key, required this.prefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _provider;
  late String _language;
  late String _overlayStyle;
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _customUrlCtrl = TextEditingController();

  // Múltiplas chaves para todos os providers
  final Map<String, List<TextEditingController>> _keys = {};
  final Map<String, int> _activeIdx = {};

  @override
  void initState() {
    super.initState();
    final prefs = widget.prefs;
    _provider = prefs.getString('provider') ?? 'openai';
    _language = prefs.getString('language') ?? 'Português';
    _overlayStyle = prefs.getString('overlay_style') ?? 'dark';
    _modelCtrl.text = prefs.getString('model') ?? '';
    _customUrlCtrl.text = prefs.getString('custom_base_url') ?? '';

    for (final p in _providers) {
      final raw = prefs.getString('api_keys_list_$p') ?? '[]';
      final List<dynamic> list = jsonDecode(raw);
      if (list.isEmpty) {
        final old = prefs.getString('api_key_$p') ?? '';
        _keys[p] = [TextEditingController(text: old)];
      } else {
        _keys[p] = list.map((k) => TextEditingController(text: k.toString())).toList();
      }
      _activeIdx[p] = prefs.getInt('api_key_active_idx_$p') ?? 0;
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _customUrlCtrl.dispose();
    for (final list in _keys.values) {
      for (final c in list) c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final prefs = widget.prefs;
    prefs.setString('provider', _provider);
    prefs.setString('language', _language);
    prefs.setString('overlay_style', _overlayStyle);
    prefs.setString('model', _modelCtrl.text.trim());
    prefs.setString('custom_base_url', _customUrlCtrl.text.trim());

    for (final p in _providers) {
      final keys = _keys[p]!.map((c) => c.text.trim()).where((k) => k.isNotEmpty).toList();
      prefs.setString('api_keys_list_$p', jsonEncode(keys));
      final idx = (_activeIdx[p] ?? 0).clamp(0, keys.isEmpty ? 0 : keys.length - 1);
      prefs.setInt('api_key_active_idx_$p', idx);
      if (keys.isNotEmpty) prefs.setString('api_key_$p', keys[idx]);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configurações salvas!'),
        backgroundColor: Color(0xFF6C63FF),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Configurações', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Salvar', style: TextStyle(color: Color(0xFF03DAC6))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Provedor de IA'),
          _card(
            DropdownButtonFormField<String>(
              value: _provider,
              dropdownColor: const Color(0xFF16213E),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Provedor ativo'),
              items: _providers
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
                  .toList(),
              onChanged: (v) => setState(() => _provider = v!),
            ),
          ),
          const SizedBox(height: 8),
          _card(
            TextField(
              controller: _modelCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Modelo (deixe vazio para padrão)'),
            ),
          ),
          if (_provider == 'custom') ...[
            const SizedBox(height: 8),
            _card(
              TextField(
                controller: _customUrlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Base URL (ex: http://localhost:11434/v1)'),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _sectionTitle('API Keys'),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Adicione quantas chaves quiser por provedor. Selecione (●) qual usar como ativa.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),

          for (final p in _providers) _keySection(p),

          const SizedBox(height: 16),
          _sectionTitle('Idioma de destino'),
          _card(
            DropdownButtonFormField<String>(
              value: _language,
              dropdownColor: const Color(0xFF16213E),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Traduzir para'),
              items: _languages
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _language = v!),
            ),
          ),

          const SizedBox(height: 16),
          _sectionTitle('Fundo do overlay'),
          _card(
            DropdownButtonFormField<String>(
              value: _overlayStyle,
              dropdownColor: const Color(0xFF16213E),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Estilo da caixa de tradução'),
              items: _overlayStyles.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _overlayStyle = v!),
            ),
          ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Salvar Configurações'),
          ),
        ],
      ),
    );
  }

  Widget _keySection(String provider) {
    final keys = _keys[provider]!;
    final activeIdx = _activeIdx[provider] ?? 0;
    final isActive = _provider == provider;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isActive)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('ATIVO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              Text(
                provider.toUpperCase(),
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => keys.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 15, color: Color(0xFF03DAC6)),
                label: const Text('Adicionar', style: TextStyle(color: Color(0xFF03DAC6), fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < keys.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Radio<int>(
                    value: i,
                    groupValue: activeIdx,
                    activeColor: const Color(0xFF6C63FF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _activeIdx[provider] = v!),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeIdx == i && isActive
                            ? const Color(0xFF1E1A3A)
                            : const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(8),
                        border: activeIdx == i && isActive
                            ? Border.all(color: const Color(0xFF6C63FF), width: 1)
                            : null,
                      ),
                      child: TextField(
                        controller: keys[i],
                        obscureText: true,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration(
                          activeIdx == i ? 'Chave ${i + 1} (ativa)' : 'Chave ${i + 1}',
                        ),
                      ),
                    ),
                  ),
                  if (keys.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => setState(() {
                        keys[i].dispose();
                        keys.removeAt(i);
                        if ((_activeIdx[provider] ?? 0) >= keys.length) {
                          _activeIdx[provider] = keys.length - 1;
                        }
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF6C63FF),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      );
}
