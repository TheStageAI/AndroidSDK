import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../../backend/voice_agent_controller.dart';
import 'agent_status.dart';

// ============================================================================
// FRONTEND widget — bottom control bar
// ============================================================================
// Shows the current status line, a live mic-level meter (while listening), a
// speaking meter fed by `tts_levels` (while speaking), and
// the Start/Stop + Interrupt controls. All behaviour is delegated to the
// controller via [onToggleRun] and `controller.interrupt`.
// ============================================================================
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.controller,
    required this.onToggleRun,
  });

  final VoiceAgentController controller;
  final VoidCallback onToggleRun;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Add the system navigation-bar inset (Samsung's on-screen
    // button / gesture bar) to the bottom padding so the Start /
    // Interrupt controls aren't hidden behind it.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            agentStateLabel(controller),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          if (controller.state == TSAgentState.listening) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: controller.vadLevel.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: controller.vadLevel > 0.5
                    ? Colors.green
                    : colorScheme.primary,
              ),
            ),
          ],
          if (controller.state == TSAgentState.speaking) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: controller.ttsLevel.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                // Disabled while a start (model load) or stop is in
                // flight, so a second tap cannot race the first.
                child: ElevatedButton(
                  onPressed: controller.busy ||
                          controller.state == TSAgentState.loading
                      ? null
                      : onToggleRun,
                  child: Text(
                    controller.starting
                        ? 'Starting...'
                        : controller.isRunning
                            ? 'Stop'
                            : 'Start',
                  ),
                ),
              ),
              if (controller.canInterrupt) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: controller.interrupt,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  child: const Text('Interrupt'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
