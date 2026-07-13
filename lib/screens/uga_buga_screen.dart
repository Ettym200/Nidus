import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_config.dart';

class UgaBugaScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const UgaBugaScreen({super.key, required this.prefs});

  @override
  State<UgaBugaScreen> createState() => _UgaBugaScreenState();
}

class _UgaBugaScreenState extends State<UgaBugaScreen> {
  final _input = TextEditingController();
  final _picker = ImagePicker();
  final List<Uint8List> _images = [];
  String _output = '';
  String _status = '';
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      _images.add(bytes);
    }
    setState(() => _status = '${_images.length} imagem(ns)');
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    _images.add(await file.readAsBytes());
    setState(() => _status = '${_images.length} imagem(ns)');
  }

  void _removeImage(int i) {
    setState(() {
      _images.removeAt(i);
      _status = _images.isEmpty ? '' : '${_images.length} imagem(ns)';
    });
  }

  void _clearAll() {
    setState(() {
      _input.clear();
      _images.clear();
      _output = '';
      _status = '';
    });
  }

  Future<void> _generate() async {
    if (_input.text.trim().isEmpty && _images.isEmpty) {
      setState(() => _status = 'Cole texto ou adicione prints');
      return;
    }
    final msg = missingApiKeyMessage(widget.prefs);
    if (msg != null) {
      setState(() => _status = msg);
      return;
    }
    final t = translatorFromPrefs(widget.prefs)!;
    setState(() {
      _busy = true;
      _status = 'IA pensando como caverna...';
    });
    try {
      final result = await t.summarizeUgaBuga(
        text: _input.text,
        images: List.from(_images),
      );
      setState(() {
        _output = result;
        _status = 'Uga uga concluído';
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
        title: const Text('Uga Buga', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _clearAll,
            child: const Text('Limpar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cole o texto da skill/item ou prints. A IA resume no estilo uga buga.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _generate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(_busy ? 'Gerando...' : 'Gerar resumo uga buga'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Galeria'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF03DAC6)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Câmera'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF03DAC6)),
                ),
                const Spacer(),
                if (_status.isNotEmpty)
                  Flexible(
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Entrada', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Texto da skill (opcional se tiver print)...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF16213E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _images[i],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeImage(i),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6B1A1A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Resumo uga buga', style: TextStyle(color: Color(0xFFE94560), fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy, size: 16, color: Color(0xFF03DAC6)),
                  label: const Text('Copiar', style: TextStyle(color: Color(0xFF03DAC6))),
                ),
              ],
            ),
            Expanded(
              flex: 2,
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
                      color: _output.isEmpty ? Colors.white38 : const Color(0xFFF4D35E),
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
