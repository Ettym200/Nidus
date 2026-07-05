import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('game_translator/overlay');
  bool _overlayActive = false;
  String _status = 'Pronto';

  @override
  void initState() {
    super.initState();
    _syncOverlayState();
  }

  Future<void> _syncOverlayState() async {
    try {
      final running = await _channel.invokeMethod<bool>('isOverlayRunning') ?? false;
      if (mounted) {
        setState(() {
          _overlayActive = running;
          if (running) _status = 'Overlay ativo! Minimize o app e use o botão flutuante';
        });
      }
    } catch (_) {}
  }

  Future<void> _startOverlay() async {
    final prefs = widget.prefs;
    final provider = prefs.getString('provider') ?? 'openai';
    final apiKey = prefs.getString('api_key_$provider') ?? '';
    final model = prefs.getString('model') ?? '';
    final language = prefs.getString('language') ?? 'Português';
    final customUrl = prefs.getString('custom_base_url') ?? '';

    if (apiKey.isEmpty) {
      setState(() => _status = 'Configure sua API key primeiro!');
      return;
    }

    try {
      // Pede permissão de overlay se necessário
      final hasPermission = await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      if (!hasPermission) {
        setState(() => _status = 'Solicitando permissão de overlay...');
        final granted = await _channel.invokeMethod<bool>('requestOverlayPermission') ?? false;
        if (!granted) {
          setState(() => _status = 'Permissão negada. Ative em Configurações → Apps → Permissão especial → Exibir sobre outros apps');
          return;
        }
      }

      setState(() => _status = 'Iniciando overlay...');
      await _channel.invokeMethod('startOverlay', {
        'apiKey': apiKey,
        'provider': provider,
        'model': model,
        'language': language,
        'customUrl': customUrl,
      });

      setState(() {
        _overlayActive = true;
        _status = 'Overlay ativo! Minimize o app e use o botão 🌐';
      });
    } catch (e) {
      setState(() => _status = 'Erro: $e');
    }
  }

  Future<void> _stopOverlay() async {
    try {
      await _channel.invokeMethod('stopOverlay');
      setState(() {
        _overlayActive = false;
        _status = 'Overlay desativado';
      });
    } catch (e) {
      setState(() => _status = 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          'Nidus',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(prefs: widget.prefs),
                ),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Aviso de gratuidade
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF03DAC6), width: 1),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF03DAC6), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Este aplicativo é totalmente gratuito. Nada aqui é pago e '
                      'nunca será. Se alguém te vendeu o Nidus, você está sendo '
                      'enganado. Se quiser, pode apoiar o projeto voluntariamente. 💙',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Ícone central
            Center(
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _overlayActive ? Colors.green : const Color(0xFF6C63FF),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    '🌐',
                    style: TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _overlayActive ? Icons.circle : Icons.circle_outlined,
                    color: _overlayActive ? Colors.green : Colors.grey,
                    size: 12,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Como usar
            if (!_overlayActive) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Como usar:', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 10),
                    Text('1. Configure sua API key (⚙️)', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 6),
                    Text('2. Toque em "Ativar Overlay"', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 6),
                    Text('3. Minimize o app e abra o jogo', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 6),
                    Text('4. Toque no botão 🌐 flutuante', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 6),
                    Text('5. Arraste para selecionar o texto', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 6),
                    Text('6. A tradução aparece na tela!', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Botão principal
            ElevatedButton.icon(
              onPressed: _overlayActive ? _stopOverlay : _startOverlay,
              icon: Icon(_overlayActive ? Icons.stop : Icons.play_arrow),
              label: Text(_overlayActive ? 'Desativar Overlay' : 'Ativar Overlay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _overlayActive ? Colors.red : const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),

            if (_overlayActive) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => SystemNavigator.pop(),
                icon: const Icon(Icons.minimize),
                label: const Text('Minimizar e ir para o jogo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF03DAC6),
                  side: const BorderSide(color: Color(0xFF03DAC6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _showDonation,
              icon: const Icon(Icons.favorite, color: Color(0xFFE94560), size: 18),
              label: const Text(
                'Apoiar via Pix',
                style: TextStyle(color: Color(0xFFE94560), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDonation() {
    const pixKey =
        '00020126580014BR.GOV.BCB.PIX01364df31385-39ad-4587-9a8b-72bb281d15905204000053039865802BR5917Jeferson Marciano6009SAO PAULO62140510AATRReYlC6630486CC';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DonationSheet(pixKey: pixKey),
    );
  }
}

class _DonationSheet extends StatefulWidget {
  final String pixKey;
  const _DonationSheet({required this.pixKey});

  @override
  State<_DonationSheet> createState() => _DonationSheetState();
}

class _DonationSheetState extends State<_DonationSheet> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.pixKey));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite, color: Color(0xFFE94560), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Apoiar o projeto',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se o app te ajudou, considere apoiar via Pix!',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E17),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chave Pix (copia e cola):',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  widget.pixKey,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _copy,
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
            label: Text(_copied ? 'Copiado!' : 'Copiar chave Pix'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _copied ? Colors.green : const Color(0xFFE94560),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Jeferson Marciano — São Paulo',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
