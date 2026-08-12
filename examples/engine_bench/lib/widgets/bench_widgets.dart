import 'package:flutter/material.dart';

import '../backend/bench_session.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

// ----------------------------------------------------------------------
// BenchScaffold — shared per-tab page chrome + Share action
// ----------------------------------------------------------------------
class BenchScaffold extends StatelessWidget {
  const BenchScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [ShareSessionButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ShareSessionButton — exports the whole session as a .json file
// ----------------------------------------------------------------------
class ShareSessionButton extends StatelessWidget {
  const ShareSessionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BenchSession.instance,
      builder: (context, _) {
        final empty = BenchSession.instance.isEmpty;
        return IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Export session JSON',
          onPressed: empty
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final path = await BenchSession.instance.share();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Saved $path')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                },
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// ModelChips — segmented-style single-select over a model list
// ----------------------------------------------------------------------
class ModelChips<T> extends StatelessWidget {
  const ModelChips({
    super.key,
    required this.models,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final List<T> models;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: models.map((m) {
        return ChoiceChip(
          label: Text(label(m)),
          selected: m == selected,
          onSelected: enabled ? (_) => onSelected(m) : null,
        );
      }).toList(),
    );
  }
}

// ----------------------------------------------------------------------
// StepperTile — labelled integer stepper (max tokens / run count)
// ----------------------------------------------------------------------
class StepperTile extends StatelessWidget {
  const StepperTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label $value', style: _mono),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: enabled && value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: enabled && value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// LoadProgress — download/compile phase indicator
// ----------------------------------------------------------------------
class LoadProgress extends StatelessWidget {
  const LoadProgress({
    super.key,
    required this.phase,
    required this.fraction,
  });

  final String phase;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    // Only `downloading` carries a meaningful fraction; the others are
    // coarse/blocking, so show an indeterminate bar for them.
    final determinate = phase == 'downloading' && fraction > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: determinate ? fraction : null),
          const SizedBox(height: 4),
          Text(
            determinate
                ? '$phase ${(fraction * 100).toStringAsFixed(0)}%'
                : '$phase...',
            style: _mono,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ActionRow — Generate + Benchmark buttons
// ----------------------------------------------------------------------
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.running,
    required this.onGenerate,
    required this.onBenchmark,
    this.generateLabel = 'Generate',
  });

  final bool running;
  final VoidCallback onGenerate;
  final VoidCallback onBenchmark;
  final String generateLabel;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: FilledButton(
          onPressed: running ? null : onGenerate,
          child: Text(running ? '...' : generateLabel),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton.tonal(
          onPressed: running ? null : onBenchmark,
          child: Text(running ? '...' : 'Benchmark'),
        ),
      ),
    ]);
  }
}

// ----------------------------------------------------------------------
// OutputBox — scrollable generated-text panel
// ----------------------------------------------------------------------
class OutputBox extends StatelessWidget {
  const OutputBox({super.key, required this.text, this.minHeight = 140});

  final String text;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(text.isEmpty ? ' ' : text),
    );
  }
}

// ----------------------------------------------------------------------
// StatusLine — monospace status / stats footer
// ----------------------------------------------------------------------
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: _mono);
  }
}
