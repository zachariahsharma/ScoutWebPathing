import 'package:flutter/material.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';

class ScoutingMatchEditor extends StatelessWidget {
  final ObservedAuto auto;
  final String activeMatchId;
  final String documentKey;
  final ValueChanged<String?> onSelectMatch;
  final VoidCallback onAddMatch;
  final VoidCallback onRemoveMatch;
  final ValueChanged<String> onRenameMatchNumber;
  final ValueChanged<bool> onSetCanMirror;
  final void Function(int rotation, bool enabled) onToggleMirrorRotation;
  final ValueChanged<String?> onSetAutoType;
  final void Function(int index, String value) onSetWaypointTiming;
  final void Function(String markerId, String value) onSetMarkerTiming;
  final void Function(String markerId, String value) onSetMarkerName;
  final void Function(String markerId, bool value) onSetMarkerToCenter;
  final void Function(String markerId, int? passNumber) onSetMarkerPass;

  const ScoutingMatchEditor({
    super.key,
    required this.auto,
    required this.activeMatchId,
    required this.documentKey,
    required this.onSelectMatch,
    required this.onAddMatch,
    required this.onRemoveMatch,
    required this.onRenameMatchNumber,
    required this.onSetCanMirror,
    required this.onToggleMirrorRotation,
    required this.onSetAutoType,
    required this.onSetWaypointTiming,
    required this.onSetMarkerTiming,
    required this.onSetMarkerName,
    required this.onSetMarkerToCenter,
    required this.onSetMarkerPass,
  });

  @override
  Widget build(BuildContext context) {
    final matches = auto.effectiveMatches();
    final activeMatch = auto.matchById(activeMatchId);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Match Details', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'match-selector-${activeMatch.id}-${activeMatch.displayLabel}',
                        ),
                        initialValue: activeMatch.id,
                        decoration: const InputDecoration(
                          labelText: 'Match',
                          prefixIcon: Icon(Icons.sports_score_outlined),
                        ),
                        items: [
                          for (final match in matches)
                            DropdownMenuItem(
                              value: match.id,
                              child: Text(match.displayLabel),
                            ),
                        ],
                        onChanged: onSelectMatch,
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextFormField(
                        key: ValueKey(
                          'match-number-$documentKey-${activeMatch.id}',
                        ),
                        initialValue: activeMatch.matchNumber,
                        decoration: const InputDecoration(
                          labelText: 'Match number',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                        onChanged: onRenameMatchNumber,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddMatch,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Match'),
                    ),
                    OutlinedButton.icon(
                      onPressed: matches.length <= 1 ? null : onRemoveMatch,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Remove Match'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final match in matches)
                      Chip(
                        backgroundColor: match.id == activeMatch.id
                            ? scheme.primary.withValues(alpha: 0.16)
                            : scheme.surfaceContainer,
                        label: Text(match.displayLabel),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MirrorCard(
          auto: auto,
          onSetCanMirror: onSetCanMirror,
          onToggleMirrorRotation: onToggleMirrorRotation,
        ),
        const SizedBox(height: 12),
        _TimingCard(
          activeMatch: activeMatch,
          documentKey: documentKey,
          onSetWaypointTiming: onSetWaypointTiming,
          onSetMarkerTiming: onSetMarkerTiming,
          onSetMarkerName: onSetMarkerName,
          onSetMarkerToCenter: onSetMarkerToCenter,
          onSetMarkerPass: onSetMarkerPass,
        ),
        const SizedBox(height: 12),
        _AutoTypeCard(auto: auto, onSetAutoType: onSetAutoType),
      ],
    );
  }
}

class _MirrorCard extends StatelessWidget {
  final ObservedAuto auto;
  final ValueChanged<bool> onSetCanMirror;
  final void Function(int rotation, bool enabled) onToggleMirrorRotation;

  const _MirrorCard({
    required this.auto,
    required this.onSetCanMirror,
    required this.onToggleMirrorRotation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mirror', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SwitchListTile(
              value: auto.canMirror,
              onChanged: onSetCanMirror,
              contentPadding: EdgeInsets.zero,
              title: const Text('Can be mirrored'),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in const [
                  (90, 'Other Side Same Alliance'),
                  (270, 'Other Side Other Alliance'),
                  (180, 'Same Side Other Alliance'),
                ])
                  FilterChip(
                    selected: auto.mirrorRotations.contains(option.$1),
                    onSelected: auto.canMirror
                        ? (value) => onToggleMirrorRotation(option.$1, value)
                        : null,
                    label: Text(option.$2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimingCard extends StatelessWidget {
  final ObservedMatchObservation activeMatch;
  final String documentKey;
  final void Function(int index, String value) onSetWaypointTiming;
  final void Function(String markerId, String value) onSetMarkerTiming;
  final void Function(String markerId, String value) onSetMarkerName;
  final void Function(String markerId, bool value) onSetMarkerToCenter;
  final void Function(String markerId, int? passNumber) onSetMarkerPass;

  const _TimingCard({
    required this.activeMatch,
    required this.documentKey,
    required this.onSetWaypointTiming,
    required this.onSetMarkerTiming,
    required this.onSetMarkerName,
    required this.onSetMarkerToCenter,
    required this.onSetMarkerPass,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Match Timings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text('Waypoints', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (int i = 0; i < activeMatch.waypointTimings.length; i++)
                  _WaypointTimingField(
                    match: activeMatch,
                    index: i,
                    documentKey: documentKey,
                    onChanged: onSetWaypointTiming,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Path Timestamps',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (activeMatch.markerTimings.isEmpty)
              Text(
                'No path timestamps yet. Right click on the path to add one.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Column(
                children: [
                  for (int i = 0; i < activeMatch.markerTimings.length; i++)
                    _MarkerTimingRow(
                      index: i,
                      timing: activeMatch.markerTimings[i],
                      matchId: activeMatch.id,
                      documentKey: documentKey,
                      isLast: i == activeMatch.markerTimings.length - 1,
                      onSetMarkerTiming: onSetMarkerTiming,
                      onSetMarkerName: onSetMarkerName,
                      onSetMarkerToCenter: onSetMarkerToCenter,
                      onSetMarkerPass: onSetMarkerPass,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _WaypointTimingField extends StatelessWidget {
  final ObservedMatchObservation match;
  final int index;
  final String documentKey;
  final void Function(int index, String value) onChanged;

  const _WaypointTimingField({
    required this.match,
    required this.index,
    required this.documentKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final timing = match.waypointTimings[index];
    final isStart = index == 0;
    final isEnd = index == match.waypointTimings.length - 1;

    return SizedBox(
      width: 180,
      child: TextFormField(
        key: ValueKey('waypoint-$documentKey-${match.id}-$index'),
        initialValue: timing.timeSeconds == null
            ? ''
            : timing.timeSeconds!.toStringAsFixed(2),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: isStart
              ? 'Start Time (s)'
              : isEnd
                  ? 'End Time (s)'
                  : 'Waypoint ${index + 1} (s)',
          hintText: 'N/A',
          prefixIcon: Icon(
            isStart
                ? Icons.play_arrow_rounded
                : isEnd
                    ? Icons.flag_outlined
                    : Icons.route_outlined,
          ),
        ),
        onChanged: (value) => onChanged(index, value),
      ),
    );
  }
}

class _MarkerTimingRow extends StatelessWidget {
  final int index;
  final ObservedMarkerTiming timing;
  final String matchId;
  final String documentKey;
  final bool isLast;
  final void Function(String markerId, String value) onSetMarkerTiming;
  final void Function(String markerId, String value) onSetMarkerName;
  final void Function(String markerId, bool value) onSetMarkerToCenter;
  final void Function(String markerId, int? passNumber) onSetMarkerPass;

  const _MarkerTimingRow({
    required this.index,
    required this.timing,
    required this.matchId,
    required this.documentKey,
    required this.isLast,
    required this.onSetMarkerTiming,
    required this.onSetMarkerName,
    required this.onSetMarkerToCenter,
    required this.onSetMarkerPass,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 120, child: Text('Timestamp ${index + 1}')),
          SizedBox(
            width: 200,
            child: TextFormField(
              key: ValueKey(
                'marker-name-$documentKey-$matchId-${timing.markerId}',
              ),
              initialValue: timing.name,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.label_outline),
              ),
              onChanged: (value) => onSetMarkerName(timing.markerId, value),
            ),
          ),
          SizedBox(
            width: 160,
            child: TextFormField(
              key: ValueKey(
                'marker-$documentKey-$matchId-${timing.markerId}',
              ),
              initialValue: timing.timeSeconds == null
                  ? ''
                  : timing.timeSeconds!.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Time (s)',
                hintText: 'N/A',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              onChanged: (value) => onSetMarkerTiming(timing.markerId, value),
            ),
          ),
          SizedBox(
            width: 210,
            child: CheckboxListTile(
              key: ValueKey(
                'center-$matchId-${timing.markerId}-${timing.isToCenter}',
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: timing.isToCenter,
              title: const Text('This to center'),
              onChanged: (value) =>
                  onSetMarkerToCenter(timing.markerId, value ?? false),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<int>(
              key: ValueKey(
                'pass-$matchId-${timing.markerId}-${timing.passNumber}',
              ),
              initialValue: timing.isToCenter ? (timing.passNumber ?? 1) : 1,
              decoration: const InputDecoration(
                labelText: 'Pass to center',
                prefixIcon: Icon(Icons.swap_horiz_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Pass 1')),
                DropdownMenuItem(value: 2, child: Text('Pass 2')),
                DropdownMenuItem(value: 3, child: Text('Pass 3')),
                DropdownMenuItem(value: 4, child: Text('Pass 4')),
              ],
              onChanged: timing.isToCenter
                  ? (value) => onSetMarkerPass(timing.markerId, value)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoTypeCard extends StatelessWidget {
  final ObservedAuto auto;
  final ValueChanged<String?> onSetAutoType;

  const _AutoTypeCard({required this.auto, required this.onSetAutoType});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auto Type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                key: ValueKey('auto-type-${auto.autoType}'),
                initialValue: auto.autoType.isEmpty ? null : auto.autoType,
                decoration: const InputDecoration(
                  labelText: 'Which auto is this?',
                  prefixIcon: Icon(Icons.assistant_direction_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'middle', child: Text('Middle auto')),
                  DropdownMenuItem(
                    value: 'tower-side',
                    child: Text('Tower-side auto'),
                  ),
                  DropdownMenuItem(
                    value: 'bump-side',
                    child: Text('Bump-side auto'),
                  ),
                ],
                onChanged: onSetAutoType,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
