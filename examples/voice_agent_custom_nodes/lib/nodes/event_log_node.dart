import 'package:thestage_android_sdk/thestage_android_sdk.dart';

/// Teaching example: listen to the internal agent bus via [onEvent].
///
/// Attached to the native graph through `agent.start(extraNodes: [...])`.
/// Every bus event the agent publishes (state changes, transcripts,
/// deltas, errors, custom-node ports) is forwarded to [onBusEvent] so the
/// host can render a live event log without knowing the SDK internals.
class EventLogNode extends TheStageAgentNode {
  EventLogNode({
    this.id = 'event_log',
    this.onBusEvent,
  });

  @override
  final String id;

  // Empty runWhen = always gated open; the node observes every state.
  @override
  final List<String> runWhen = const [];

  final void Function(Map<String, dynamic> event)? onBusEvent;

  @override
  Future<void> onEvent(
    AgentNodeContext context,
    Map<String, dynamic> event,
  ) async {
    onBusEvent?.call(event);
  }
}
