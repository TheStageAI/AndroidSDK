import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/voice_agent_controller.dart';

// ============================================================================
// FRONTEND — Custom Nodes panel
// ============================================================================
// Surfaces everything the demo adds on top of the plain voice agent:
//   • sendRequest — inject a typed user turn (LLM → TTS), no mic.
//   • VLM caption — pick an image, caption it with the ephemeral lfm2-vl
//     model (only while the agent is in a quiet state).
//   • Screen record — TheStageScreenRecorder (native stub this round, so a
//     friendly SnackBar replaces a crash).
//   • Event Log — the internal agent bus, mirrored by EventLogNode.
//
// Everything reads from [VoiceAgentController]; this screen owns no SDK
// state of its own.
// ============================================================================
class CustomNodesScreen extends StatefulWidget {
  const CustomNodesScreen({super.key, required this.controller});

  final VoiceAgentController controller;

  @override
  State<CustomNodesScreen> createState() => _CustomNodesScreenState();
}

class _CustomNodesScreenState extends State<CustomNodesScreen> {
  final _sendCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _recording = false;
  bool _captioning = false;

  @override
  void initState() {
    super.initState();
    _refreshRecordingState();
  }

  @override
  void dispose() {
    _sendCtrl.dispose();
    super.dispose();
  }

  VoiceAgentController get _c => widget.controller;

  Future<void> _refreshRecordingState() async {
    try {
      final r = await TheStageScreenRecorder.isRecording();
      if (mounted) setState(() => _recording = r);
    } catch (_) {
      // Stub / unavailable — leave the button in its idle state.
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final t = _sendCtrl.text.trim();
    if (t.isEmpty) return;
    await _c.sendText(t);
    _sendCtrl.clear();
  }

  Future<void> _pickAndCaption() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _captioning = true);
    try {
      await _c.captionImage(file.path);
    } finally {
      if (mounted) setState(() => _captioning = false);
    }
  }

  Future<void> _toggleRecord() async {
    try {
      if (_recording) {
        await TheStageScreenRecorder.stop();
        _snack('Recording saved to gallery.');
      } else {
        await TheStageScreenRecorder.start();
      }
      await _refreshRecordingState();
    } on PlatformException catch (e) {
      // The native recorder is a stub this round.
      if (e.code == 'screen_recorder_unavailable') {
        _snack('Screen recording coming soon.');
      } else {
        _snack('Screen recorder error: ${e.message ?? e.code}');
      }
    } catch (e) {
      _snack('Screen recorder error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Nodes')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final running = _c.isRunning;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusLine(context, running),
              const SizedBox(height: 16),

              // ── sendRequest ──
              _sectionTitle(context, 'Typed turn (sendRequest)'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sendCtrl,
                      enabled: running,
                      onSubmitted: (_) => running ? _send() : null,
                      decoration: const InputDecoration(
                        labelText: 'Ask the agent…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: running ? _send : null,
                    child: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── VLM caption ──
              _sectionTitle(context, 'VLM caption (ephemeral lfm2-vl)'),
              Text(
                'Captions run only in a quiet agent state. The VLM is '
                'started for the burst and stopped afterwards.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: running && !_captioning ? _pickAndCaption : null,
                icon: _captioning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  _captioning ? 'Captioning…' : 'Pick image → caption',
                ),
              ),
              const SizedBox(height: 8),
              if (_c.captions.isEmpty)
                Text(
                  'No captions yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._c.captions.take(8).map(
                      (c) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(c),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),

              // ── Screen record ──
              _sectionTitle(context, 'Screen record'),
              OutlinedButton.icon(
                onPressed: _toggleRecord,
                icon: Icon(
                  _recording
                      ? Icons.stop_circle_outlined
                      : Icons.fiber_manual_record,
                  color: _recording ? Colors.red : null,
                ),
                label: Text(_recording ? 'Stop recording' : 'Record screen'),
              ),
              const SizedBox(height: 20),

              // ── Event log ──
              _sectionTitle(context, 'Event log (internal bus)'),
              if (_c.busEvents.isEmpty)
                Text(
                  running
                      ? 'Waiting for bus events…'
                      : 'Start the agent to observe bus events.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _c.busEvents.take(30))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            e,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusLine(BuildContext context, bool running) {
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: running ? Colors.green : Colors.grey),
        const SizedBox(width: 8),
        Text(
          running
              ? 'Agent running · ${_c.state.name}'
              : 'Agent stopped — start it on the chat screen.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
