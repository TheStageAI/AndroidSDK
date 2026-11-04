import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/settings_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.agent,
  });
  final VoiceAgentSettings settings;
  final TSVoiceAgent agent;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  VoiceAgentSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  // The interrupt knobs also hot-apply to a running agent. The new
  // value is saved either way (it applies at the next Start); tell the
  // user when the live update did not go through.
  Future<void> _hotUpdate(Future<void> Function() call) async {
    if (widget.agent.state == TSAgentState.idle) return;
    try {
      await call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Not applied live ($e). It applies at the next '
              'Start.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _sectionHeader('On-device models'),
            _note(
              'Hugging Face repos — the SDK resolves each one to its '
              'pinned revision and the best bundle for this phone. '
              'Restart the agent after changing models.',
            ),
            if (s.llmProvider == 'local')
              _modelDropdown(
                'LLM',
                s.llmModel,
                VoiceAgentSettings.availableHfLlms,
                (v) => s.update((s) => s.llmModel = v),
              )
            else
              _readonly('LLM', '${s.llmModel} @ ${s.llmEndpoint}'),
            _modelDropdown(
              'ASR',
              s.sttRepo,
              VoiceAgentSettings.availableHfAsr,
              (v) => s.update((s) => s.sttRepo = v),
            ),
            _modelDropdown(
              'TTS',
              s.ttsRepo,
              VoiceAgentSettings.availableHfTts,
              (v) => s.update((s) => s.selectTtsRepo(v)),
            ),
            _readonly(
              'VAD / turn',
              'TheStageAI/silero-vad + ${s.turnDetectorRepo}',
            ),

            _sectionHeader('Voice & Language'),
            _dropdown('TTS Voice', s.ttsVoice, s.voices, (v) {
              s.update((s) => s.ttsVoice = v);
            }),
            _dropdown('STT Language', s.sttLanguage,
                VoiceAgentSettings.availableLanguages, (v) {
              s.update((s) => s.sttLanguage = v);
            }),
            _textField('System Prompt', s.systemPrompt, (v) {
              s.update((s) => s.systemPrompt = v);
            }, maxLines: 3),

            _sectionHeader('LLM Provider'),
            _dropdown('Provider', s.llmProvider,
                const ['local', 'openai_compatible'], (v) {
              s.update((s) => s.selectProvider(v));
            }),
            if (s.llmProvider == 'local')
              _note(
                'On-device from HF: ${s.llmModel} (the SDK\'s pinned '
                'revision). The on-device models decode greedily.',
              )
            else ...[
              _textField('Model', s.llmModel, (v) {
                s.update((s) => s.llmModel = v);
              }),
              _textField('Endpoint', s.llmEndpoint, (v) {
                s.update((s) => s.llmEndpoint = v);
              }),
              _slider('Temperature', s.temperature, 0.0, 1.5, (v) {
                s.update((s) => s.temperature = v);
              }, decimals: 2),
            ],
            _slider('Max Tokens', s.maxTokens.toDouble(), 64, 1024, (v) {
              s.update((s) => s.maxTokens = v.round());
            }),

            _sectionHeader('Endpointing'),
            // Capture (endpointing) threshold. Applied at agent start.
            _slider('VAD Threshold (capture)', s.vadThreshold, 0.3, 0.8, (v) {
              s.update((s) => s.vadThreshold = v);
            }, decimals: 2),
            _slider('VAD Onset (ms)', s.vadOnsetMs.toDouble(), 32, 320, (v) {
              s.update((s) => s.vadOnsetMs = v.round());
            }),
            _slider('Max Turn Length (ms)', s.maxAccumulationMs.toDouble(), 5000,
                60000, (v) {
              s.update((s) => s.maxAccumulationMs = v.round());
            }),
            // Only used by the VAD endpointer (DNN owns end-of-turn otherwise).
            if (!s.useDnnTurn)
              _slider('Silence Timeout (ms)', s.silenceTimeoutMs.toDouble(), 300,
                  2000, (v) {
                s.update((s) => s.silenceTimeoutMs = v.round());
              }),
  
            _sectionHeader('Turn Detection (end-of-turn)'),
            _toggle('DNN smart-turn (off = VAD silence)', s.useDnnTurn, (v) {
              s.update((s) => s.useDnnTurn = v);
            }),
            if (s.useDnnTurn) ...[
              _note('DNN turn knobs apply on next Start.'),
              _slider('EOT Threshold', s.turnEotThreshold, 0.3, 0.9, (v) {
                s.update((s) => s.turnEotThreshold = v);
              }, decimals: 2),
              _slider('EOT Confirm Count', s.turnEotConfirmCount.toDouble(), 1, 4,
                  (v) {
                s.update((s) => s.turnEotConfirmCount = v.round());
              }),
              _note('Consecutive positive verdicts before ending the turn. '
                  'Higher = fewer premature cut-offs, slightly more latency.'),
              _slider('EOT High-Confidence', s.turnEotHighConfidence, 0.6, 1.0,
                  (v) {
                s.update((s) => s.turnEotHighConfidence = v);
              }, decimals: 2),
              _note('A verdict at/above this commits immediately, skipping '
                  'confirmation. 1.0 = always confirm.'),
              _slider('Pause Trigger (ms)', s.turnPauseTriggerMs.toDouble(), 96,
                  1000, (v) {
                s.update((s) => s.turnPauseTriggerMs = v.round());
              }),
              _slider('Re-eval Interval (ms, 0=off)',
                  s.turnReevalIntervalMs.toDouble(), 0, 1000, (v) {
                s.update((s) => s.turnReevalIntervalMs = v.round());
              }),
              _slider('Max Silence Fallback (ms)',
                  s.turnMaxSilenceMs.toDouble(), 1000, 7000, (v) {
                s.update((s) => s.turnMaxSilenceMs = v.round());
              }),
              _slider('Model Window (ms)', s.turnWindowMs.toDouble(), 4000, 8000,
                  (v) {
                s.update((s) => s.turnWindowMs = v.round());
              }),
              _slider('Min Speech (ms)', s.turnMinSpeechMs.toDouble(), 0, 500,
                  (v) {
                s.update((s) => s.turnMinSpeechMs = v.round());
              }),
              _slider('ASR Silence Hangover (ms)',
                  s.turnAsrSilenceHangoverMs.toDouble(), 0, 800, (v) {
                s.update((s) => s.turnAsrSilenceHangoverMs = v.round());
              }),
            ],
  
            _sectionHeader('Streaming ASR'),
            _toggle('Live caption partials', s.asrStreaming, (v) {
              s.update((s) => s.asrStreaming = v);
            }),
            if (s.asrStreaming)
              _slider('Partial Interval (ms)',
                  s.asrPartialIntervalMs.toDouble(), 200, 1500, (v) {
                s.update((s) => s.asrPartialIntervalMs = v.round());
              }),
            _toggle('Speculative Whisper', s.speculativeWhisper, (v) {
              s.update((s) => s.speculativeWhisper = v);
            }),
  
            _sectionHeader('Diagnostics'),
            _toggle('Debug timeline log', s.debugTimeline, (v) {
              s.update((s) => s.debugTimeline = v);
            }),
            _note(
              'Logs a single cross-node event timeline. Read it with:\n'
              'adb logcat -s Timeline:I',
            ),
  
            _sectionHeader('Wake Word'),
            // Shown but blocked: a wake word recognises one specific phrase,
            // so this example ships without a model and the agent listens
            // continuously. The controls stay visible so the settings a wake
            // word would use are still discoverable.
            _note(
              'This example ships no wake-word model, so these are '
              'disabled and the agent listens continuously.',
            ),
            _toggle('Wake Word Enabled', s.wakeWordEnabled, (_) {},
                enabled: false),
            _slider('WW Threshold', s.wwThreshold, 0.5, 0.9, (_) {},
                decimals: 2, enabled: false),
            _slider('Conversation Timeout (s)',
                s.conversationTimeoutSec.toDouble(), 0, 120, (_) {},
                enabled: false),
  
            _sectionHeader('Interruption'),
            _toggle('Allow Interruptions', s.allowInterruptions, (v) {
              s.update((s) => s.allowInterruptions = v);
            }),
            if (s.allowInterruptions) ...[
              // `wake_word` is also a valid interrupt mode, but it needs a
              // wake-word model to confirm the barge-in, so it is not offered
              // here -- see the Wake Word section.
              _dropdown('Interrupt Mode', s.interruptMode, ['speech_only'], (v) {
                s.update((s) => s.interruptMode = v);
                _hotUpdate(
                  () => widget.agent.update_interrupt_config(interrupt_mode: v),
                );
              }),
              _slider('Min Speech to Interrupt (ms)',
                  s.interruptMinSpeechMs.toDouble(), 100, 1500, (v) {
                final ms = v.round();
                s.update((s) => s.interruptMinSpeechMs = ms);
                _hotUpdate(
                  () => widget.agent
                      .update_interrupt_config(interrupt_min_speech_ms: ms),
                );
              }),
              // Sustained positive-VAD time (ms) to fire a barge-in. 0 = use
              // the min-speech value above. Higher + a high interrupt
              // threshold rejects noise so the agent won't self-interrupt.
              _slider('Interrupt Onset (ms, 0=use min speech)',
                  s.interruptOnsetMs.toDouble(), 0, 640, (v) {
                final ms = v.round();
                s.update((s) => s.interruptOnsetMs = ms);
                _hotUpdate(
                  () => widget.agent
                      .update_interrupt_config(interrupt_onset_ms: ms),
                );
              }),
              // Strict barge-in threshold, separate from the capture threshold.
              _slider('Interrupt Threshold', s.interruptThreshold, 0.5, 0.96, (v) {
                s.update((s) => s.interruptThreshold = v);
                _hotUpdate(
                  () => widget.agent
                      .update_interrupt_config(interrupt_threshold: v),
                );
              }, decimals: 2),
              _note('Lockouts below apply on next Start.'),
              // Per-message grace at TTS start so AEC can re-converge.
              _slider('Playback Lockout (ms)',
                  s.interruptMinPlaybackMs.toDouble(), 0, 1000, (v) {
                s.update((s) => s.interruptMinPlaybackMs = v.round());
              }),
              // One-time longer lockout on the FIRST reply (AEC cold start).
              // Raise this if the agent self-interrupts right after (re)starting.
              _slider('Initial Lockout (ms, 1st reply)',
                  s.interruptInitialLockoutMs.toDouble(), 0, 3000, (v) {
                s.update((s) => s.interruptInitialLockoutMs = v.round());
              }),
              // Lockout while thinking (post end-of-turn, pre-TTS).
              _slider('Thinking Lockout (ms)',
                  s.interruptThinkingLockoutMs.toDouble(), 0, 2000, (v) {
                s.update((s) => s.interruptThinkingLockoutMs = v.round());
              }),
            ],
  
            _sectionHeader('Audio'),
            _slider('Pre-roll (ms)', s.preRollMs.toDouble(), 0, 500, (v) {
              s.update((s) => s.preRollMs = v.round());
            }),
            _toggle('AEC Enabled', s.aecEnabled, (v) {
              s.update((s) => s.aecEnabled = v);
            }),
            if (s.aecEnabled) ...[
              // Silence played at start so the echo canceller has a reference
              // before the first TTS. Raise for more cold-start margin.
              _slider('AEC Warmup (ms)', s.aecWarmupMs.toDouble(), 0, 1000, (v) {
                s.update((s) => s.aecWarmupMs = v.round());
              }),
              _slider('Playback Gate Tail (ms)',
                  s.aecPlaybackGateTailMs.toDouble(), 0, 500, (v) {
                s.update((s) => s.aecPlaybackGateTailMs = v.round());
              }),
            ],
  
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _dropdown(
      String label, String value, List<String> options, ValueChanged<String> onChanged) {
    // DropdownButton asserts if [value] is not in [options] — fall back.
    final effective =
        options.contains(value) ? value : (options.isEmpty ? value : options.first);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<String>(
            value: effective,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  /// Dropdown for HF / BundledModels ids — shows the short stem, stores full id.
  Widget _modelDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    final effective =
        options.contains(value) ? value : (options.isEmpty ? value : options.first);
    String short(String id) {
      final slash = id.lastIndexOf('/');
      return slash >= 0 ? id.substring(slash + 1) : id;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: effective,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: options
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: Text(
                        short(o),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {int decimals = 0, bool enabled = true}) {
    final displayValue = decimals > 0
        ? value.toStringAsFixed(decimals)
        : value.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(displayValue,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            // A null callback is how a Slider renders disabled.
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _readonly(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged,
      {bool enabled = true}) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      // A null callback is how a SwitchListTile renders disabled.
      onChanged: enabled ? onChanged : null,
      contentPadding: EdgeInsets.zero,
    );
  }

  // One controller per field, kept across rebuilds: a new one on
  // every build resets the cursor while the user types.
  final Map<String, TextEditingController> _controllers = {};

  Widget _textField(
      String label, String value, ValueChanged<String> onChanged,
      {int maxLines = 1}) {
    final controller = _controllers.putIfAbsent(
        label, () => TextEditingController(text: value));
    // The value changed elsewhere (e.g. a provider switch).
    if (controller.text != value) controller.text = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }
}
