import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TTSStreamApp());
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
class TTSStreamApp extends StatelessWidget {
  const TTSStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NeuTTS Streaming',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const TTSStreamScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class TTSStreamScreen extends StatefulWidget {
  const TTSStreamScreen({super.key});

  @override
  State<TTSStreamScreen> createState() => _TTSStreamScreenState();
}

class _TTSStreamScreenState extends State<TTSStreamScreen> {
  // Injected at build/run time via:
  //   flutter run --dart-define-from-file=secrets.json
  static const _apiToken = String.fromEnvironment('TS_API_TOKEN');

  // neutts-multilingual @ develop ships the 'paul' voice (the android
  // branch ships a different voice set); revision matches the voice.
  final _controller =
      TTSController(defaultVoice: 'paul', revision: 'develop');
  final _textController = TextEditingController(
    text: "Hey — who's the prettiest one here? It's you. You're the best, "
        "you know it, and nobody can ever take that away from you. "
        "Don't let your dreams be dreams. Just do it.",
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    if (_apiToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('TS_API_TOKEN not set. Run with '
            '--dart-define-from-file=secrets.json'),
      ));
      return;
    }
    try {
      await _controller.initialize(apiToken: _apiToken);
    } catch (e) {
      // Error already reflected in controller.status
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('NeuTTS Streaming')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgress(),
              _buildVoiceSelector(),
              const SizedBox(height: 16),
              _buildTextInput(),
              const SizedBox(height: 16),
              _buildControls(),
              const SizedBox(height: 20),
              _buildStatus(),
              _buildStats(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // UI Components
  // -------------------------------------------------------------------------
  Widget _buildProgress() {
    if (_controller.modelReady) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(children: [
        LinearProgressIndicator(
          // Only `downloading` has meaningful sub-progress. During
          // extract/compile the SDK can't report a fraction, so show an
          // animated (indeterminate) bar rather than a frozen 85%.
          value: (_controller.loadPhase == 'downloading' &&
                  _controller.downloadProgress > 0)
              ? _controller.downloadProgress
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          _controller.status,
          style: const TextStyle(color: Colors.grey),
        ),
      ]),
    );
  }

  Widget _buildVoiceSelector() {
    final enabled =
        !_controller.generating && _controller.modelReady;
    // Wrap of chips instead of a single SegmentedButton so any
    // number of voices flows onto multiple lines and never
    // overflows the row (the multilingual bundle ships several).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Voice:'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _controller.availableVoices.map((v) {
              return ChoiceChip(
                label: Text(v),
                selected: _controller.selectedVoice == v,
                onSelected: enabled
                    ? (_) => _controller.switchVoice(v)
                    : null,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      maxLines: 4,
      decoration: const InputDecoration(
        labelText: 'Text to speak',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _buildControls() {
    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _controller.modelReady && !_controller.generating
              ? () => _controller.startStream(_textController.text.trim())
              : null,
          icon: _controller.generating
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_controller.generating ? 'Streaming...' : 'Stream'),
        ),
      ),
      const SizedBox(width: 12),
      ElevatedButton.icon(
        onPressed: _controller.generating ? _controller.stopStream : null,
        icon: const Icon(Icons.stop),
        label: const Text('Stop'),
      ),
    ]);
  }

  Widget _buildStatus() {
    return Text('Status: ${_controller.status}');
  }

  Widget _buildStats() {
    final stats = _controller.stats;
    if (stats == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _StatsCard(stats: stats),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats Card
// ---------------------------------------------------------------------------
class _StatsCard extends StatelessWidget {
  final TTSStreamStats stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Menlo',
          fontSize: 13,
          color: Colors.black87,
        ),
        child: Column(children: [
          _row('First chunk',
              stats.timeToFirstAudio != null
                  ? '${(stats.timeToFirstAudio! * 1000).toInt()} ms'
                  : '...'),
          _row('Total time',
              stats.totalTime != null
                  ? '${stats.totalTime!.toStringAsFixed(2)}s'
                  : '...'),
          _row('Audio', '${stats.audioDuration.toStringAsFixed(2)}s'),
          _row('Tokens', '${stats.generatedTokens}'),
          if (stats.rtf != null)
            _row('RTF', '${stats.rtf!.toStringAsFixed(2)}x'),
          if (stats.tokensPerSecond != null)
            _row('Tok/s', stats.tokensPerSecond!.toStringAsFixed(1)),
          if (stats.memoryMB != null)
            _row('Memory (footprint)',
                '${stats.memoryMB!.toStringAsFixed(0)} MB'),
          if (stats.residentMB != null)
            _row('  └ RSS', '${stats.residentMB!.toStringAsFixed(0)} MB'),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value)],
      ),
    );
  }
}
