import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';
import 'package:pathplanner/webui/models/observed_field.dart';
import 'package:pathplanner/webui/services/webui_api.dart';
import 'package:pathplanner/webui/widgets/observed_auto_thumbnail.dart';
import 'package:pathplanner/webui/widgets/scouting_match_editor.dart';
import 'package:pathplanner/webui/widgets/scouting_pathplanner_editor.dart';
import 'package:url_launcher/url_launcher.dart';

class ScoutingWebHomePage extends StatefulWidget {
  const ScoutingWebHomePage({super.key});

  @override
  State<ScoutingWebHomePage> createState() => _ScoutingWebHomePageState();
}

enum _SaveStatus { saved, unsaved, saving, failed }

class _ScoutingWebHomePageState extends State<ScoutingWebHomePage> {
  final WebUiApi _api = WebUiApi();
  final TextEditingController _autoNameController = TextEditingController();
  final TextEditingController _teamSearchController = TextEditingController();

  List<String> _teams = [];
  List<ObservedAutoSummary> _autos = [];
  String? _selectedTeam;
  ObservedAuto? _currentAuto;
  bool _loadingTeams = true;
  bool _loadingAuto = false;
  bool _saving = false;
  bool _dirty = false;
  bool _browserCollapsed = false;
  bool _browserPreviewMode = false;
  bool _saveQueued = false;
  int _editRevision = 0;
  int _latestSaveRequest = 0;
  _SaveStatus _saveStatus = _SaveStatus.saved;
  String? _selectedMatchId;
  Timer? _autosaveTimer;
  Future<void>? _activeSave;

  @override
  void initState() {
    super.initState();
    _teamSearchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _loadTeams();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _autoNameController.dispose();
    _teamSearchController.dispose();
    super.dispose();
  }

  List<String> get _filteredTeams {
    final query = _teamSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _teams;
    }
    return _teams
        .where((team) => team.toLowerCase().contains(query))
        .toList(growable: false);
  }

  String get _saveStatusLabel {
    switch (_saveStatus) {
      case _SaveStatus.saving:
        return 'Saving...';
      case _SaveStatus.unsaved:
        return 'Unsaved';
      case _SaveStatus.failed:
        return 'Save failed';
      case _SaveStatus.saved:
        return 'Saved';
    }
  }

  IconData get _saveStatusIcon {
    switch (_saveStatus) {
      case _SaveStatus.saving:
        return Icons.sync_rounded;
      case _SaveStatus.unsaved:
        return Icons.schedule_rounded;
      case _SaveStatus.failed:
        return Icons.error_outline;
      case _SaveStatus.saved:
        return Icons.cloud_done_outlined;
    }
  }

  bool _isSavingAuto(String team, String storageId) {
    return _saving &&
        _currentAuto?.team == team &&
        _currentAuto?.storageId == storageId;
  }

  Future<void> _loadTeams({String? selectTeam}) async {
    setState(() {
      _loadingTeams = true;
    });

    try {
      final teams = await _api.fetchTeams();
      String? targetTeam = selectTeam;
      if (teams.isNotEmpty) {
        targetTeam ??=
            teams.contains(_selectedTeam) ? _selectedTeam : teams.first;
      } else {
        targetTeam = null;
      }

      setState(() {
        _teams = teams;
        _selectedTeam = targetTeam;
        _loadingTeams = false;
      });

      if (targetTeam != null) {
        await _loadAutos(targetTeam);
      } else {
        setState(() {
          _autos = [];
          _currentAuto = null;
          _dirty = false;
          _saveStatus = _SaveStatus.saved;
        });
      }
    } catch (error) {
      setState(() {
        _loadingTeams = false;
      });
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _loadAutos(String team, {String? selectStorageId}) async {
    try {
      final autos = await _api.fetchAutos(team);
      setState(() {
        _selectedTeam = team;
        _autos = autos;
      });

      if (selectStorageId != null) {
        await _openAuto(team, selectStorageId);
      } else if (_currentAuto != null &&
          _currentAuto!.team == team &&
          autos.any((auto) => auto.id == _currentAuto!.storageId)) {
        await _openAuto(team, _currentAuto!.storageId);
      } else if (autos.isNotEmpty) {
        await _openAuto(team, autos.first.id);
      } else {
        setState(() {
          _currentAuto = null;
          _dirty = false;
          _saveStatus = _SaveStatus.saved;
          _autoNameController.clear();
        });
      }
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _openAuto(String team, String storageId) async {
    setState(() {
      _loadingAuto = true;
    });

    try {
      final auto = await _api.fetchAuto(team, storageId);
      setState(() {
        _currentAuto = auto;
        _dirty = false;
        _loadingAuto = false;
        _saveStatus = _SaveStatus.saved;
        _selectedMatchId = auto.effectiveSelectedMatchId;
      });
      _autoNameController.text = auto.name;
    } catch (error) {
      setState(() {
        _loadingAuto = false;
      });
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _selectTeam(String team) async {
    await _flushAutosave();
    await _loadAutos(team);
  }

  Future<void> _selectAuto(String team, String storageId) async {
    await _flushAutosave();
    await _openAuto(team, storageId);
  }

  Future<void> _createTeam() async {
    final teamName = await _showNameDialog(
      title: 'Create Team Folder',
      label: 'Team folder name',
      initialValue: '',
    );
    if (teamName == null) {
      return;
    }

    try {
      await _api.createTeam(teamName);
      await _loadTeams(selectTeam: teamName);
      _showMessage('Created team folder "$teamName"');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _createAuto() async {
    if (_selectedTeam == null) {
      _showMessage('Create or select a team first.', isError: true);
      return;
    }

    final autoName = await _showNameDialog(
      title: 'Create Auto',
      label: 'Auto name',
      initialValue: 'New Auto',
    );
    if (autoName == null) {
      return;
    }

    try {
      final created = await _api.saveAuto(
        ObservedAuto.empty(team: _selectedTeam!, name: autoName),
      );
      setState(() {
        _currentAuto = created;
        _dirty = false;
        _saveStatus = _SaveStatus.saved;
        _autos = _upsertSummary(_autos, _summaryFromAuto(created));
        _selectedMatchId = created.effectiveSelectedMatchId;
      });
      _autoNameController.text = created.name;
      await _openAuto(created.team, created.storageId);
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _deleteAuto(String team, ObservedAutoSummary auto) async {
    final confirmed = await _showDeleteAutoDialog(auto.name);
    if (confirmed != true) {
      return;
    }

    final deletingCurrent =
        _currentAuto?.team == team && _currentAuto?.storageId == auto.id;
    if (deletingCurrent && _saving) {
      _showMessage('Wait for the current save to finish before deleting.',
          isError: true);
      return;
    }

    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final deletedIndex = _autos.indexWhere((entry) => entry.id == auto.id);

    try {
      await _api.deleteAuto(team, auto.id);

      final remaining = [
        for (final entry in _autos)
          if (entry.id != auto.id) entry,
      ];
      final nextIndex =
          deletedIndex < 0 ? 0 : min(deletedIndex, remaining.length - 1);
      final nextAutoId = deletingCurrent && remaining.isNotEmpty
          ? remaining[nextIndex].id
          : null;

      setState(() {
        _autos = remaining;
        if (deletingCurrent) {
          _currentAuto = null;
          _dirty = false;
          _saveStatus = _SaveStatus.saved;
          _selectedMatchId = null;
          _autoNameController.clear();
        }
      });

      if (nextAutoId != null) {
        await _openAuto(team, nextAutoId);
      }

      _showMessage('Deleted "${auto.name}"');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _saveCurrentAuto({bool silent = false}) async {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    if (_saving) {
      _saveQueued = true;
      final activeSave = _activeSave;
      if (activeSave != null) {
        await activeSave;
      }
      if (_dirty && _currentAuto != null) {
        await _saveCurrentAuto(silent: silent);
      }
      return;
    }

    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final saveRevision = _editRevision;
    final saveRequest = ++_latestSaveRequest;
    final activeSave = Completer<void>();
    _activeSave = activeSave.future;

    setState(() {
      _saving = true;
      _saveStatus = _SaveStatus.saving;
    });

    try {
      final sanitized = auto.copyWith(
        name: _autoNameController.text.trim().isEmpty
            ? auto.name
            : _autoNameController.text.trim(),
        selectedMatchId: _selectedMatchId,
      );
      final saved = await _api.saveAuto(sanitized);
      final stillCurrent =
          _currentAuto != null && _isSameDocument(_currentAuto!, auto);
      final saveIsLatest = saveRequest == _latestSaveRequest;
      final hasNewerEdits = _editRevision > saveRevision;

      setState(() {
        _saving = false;
        if (stillCurrent && saveIsLatest) {
          _autos = _upsertSummary(_autos, _summaryFromAuto(saved));
          _currentAuto = saved;
          _selectedMatchId = saved.effectiveSelectedMatchId;
        } else if (_selectedTeam == saved.team) {
          _autos = _upsertSummary(_autos, _summaryFromAuto(saved));
        }

        if (stillCurrent && saveIsLatest && !hasNewerEdits) {
          _dirty = false;
          _saveStatus = _SaveStatus.saved;
        } else if (_dirty) {
          _saveStatus = _SaveStatus.unsaved;
        }
      });

      if (stillCurrent && saveIsLatest && !hasNewerEdits) {
        _autoNameController.value = TextEditingValue(
          text: saved.name,
          selection: TextSelection.collapsed(offset: saved.name.length),
        );
      }

      if (!silent) {
        _showMessage('Saved "${saved.name}"');
      }
    } catch (error) {
      setState(() {
        _saving = false;
        _saveStatus = _SaveStatus.failed;
      });
      if (!silent) {
        _showMessage(error.toString(), isError: true);
      }
    } finally {
      activeSave.complete();
      if (identical(_activeSave, activeSave.future)) {
        _activeSave = null;
      }
      if (_saveQueued || _editRevision > saveRevision) {
        _saveQueued = false;
        if (_dirty && _currentAuto != null) {
          unawaited(_saveCurrentAuto(silent: true));
        }
      }
    }
  }

  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_dirty && _currentAuto != null) {
      await _saveCurrentAuto(silent: true);
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (_currentAuto == null) {
      return;
    }
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveCurrentAuto(silent: true));
    });
  }

  Future<void> _exportCurrentAuto() async {
    if (_currentAuto == null) {
      return;
    }
    await _flushAutosave();
    final auto = _currentAuto;
    if (auto == null || auto.storageId.isEmpty) {
      return;
    }

    final launched = await launchUrl(_api.exportUri(auto));
    if (!launched && mounted) {
      _showMessage('Failed to open export URL.', isError: true);
    }
  }

  Future<void> _exportCurrentRenderJpeg() async {
    if (_currentAuto == null) {
      return;
    }
    await _flushAutosave();
    final auto = _currentAuto;
    if (auto == null || auto.storageId.isEmpty) {
      return;
    }

    final launched = await launchUrl(
      _api.renderAutoJpegUri(auto, matchId: _selectedMatchId),
    );
    if (!launched && mounted) {
      _showMessage('Failed to open render export URL.', isError: true);
    }
  }

  Future<void> _exportCurrentTeamPdf() async {
    final team = _selectedTeam;
    if (team == null) {
      return;
    }
    await _flushAutosave();
    final launched = await launchUrl(_api.exportTeamPdfUri(team));
    if (!launched && mounted) {
      _showMessage('Failed to open team PDF export URL.', isError: true);
    }
  }

  void _updateAuto(ObservedAuto auto, {bool dirty = true}) {
    setState(() {
      _currentAuto = auto;
      _dirty = dirty;
      if (dirty) {
        _editRevision++;
        _saveStatus = _SaveStatus.unsaved;
      } else {
        _saveStatus = _SaveStatus.saved;
      }
    });
    if (dirty) {
      _scheduleAutosave();
    }
  }

  bool _isSameDocument(ObservedAuto a, ObservedAuto b) {
    if (a.team != b.team) {
      return false;
    }
    if (a.storageId.isNotEmpty && b.storageId.isNotEmpty) {
      return a.storageId == b.storageId;
    }
    return a.createdAt == b.createdAt;
  }

  ObservedAutoSummary _summaryFromAuto(ObservedAuto auto) {
    return ObservedAutoSummary.fromAuto(auto);
  }

  List<ObservedAutoSummary> _upsertSummary(
    List<ObservedAutoSummary> autos,
    ObservedAutoSummary summary,
  ) {
    final next = [
      for (final auto in autos)
        if (auto.id != summary.id) auto,
      summary,
    ];
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return next;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            isError ? Theme.of(context).colorScheme.errorContainer : null,
        content: Text(message),
      ),
    );
  }

  Future<String?> _showNameDialog({
    required String title,
    required String label,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (_) =>
                Navigator.of(context).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((value) {
      controller.dispose();
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return value.trim();
    });
  }

  Future<bool?> _showDeleteAutoDialog(String autoName) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Auto'),
          content: Text('Delete "$autoName"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 1180;
            final browser = _buildBrowserPanel(context);
            final editor = _buildEditorPanel(context);

            if (stacked) {
              final browserHeight = _browserCollapsed ? 84.0 : 320.0;
              return Column(
                children: [
                  SizedBox(height: browserHeight, child: browser),
                  const Divider(height: 1),
                  Expanded(child: editor),
                ],
              );
            }

            final browserWidth = _browserCollapsed
                ? 74.0
                : (_browserPreviewMode ? 560.0 : 340.0);

            return Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: browserWidth,
                  child: browser,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: editor),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrowserPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filteredTeams = _filteredTeams;
    final team = _selectedTeam;

    if (_browserCollapsed) {
      return ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            const SizedBox(height: 12),
            IconButton(
              tooltip: 'Expand sidebar',
              onPressed: () {
                setState(() {
                  _browserCollapsed = false;
                });
              },
              icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
            ),
            const SizedBox(height: 8),
            IconButton(
              tooltip: 'Create team',
              onPressed: _createTeam,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            IconButton(
              tooltip: 'Create auto',
              onPressed: team == null ? null : _createAuto,
              icon: const Icon(Icons.add_circle_outline),
            ),
            const Spacer(),
            if (team != null)
              RotatedBox(
                quarterTurns: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Scouting Autos',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: _browserPreviewMode ? 'List view' : 'Preview view',
                  onPressed: () {
                    setState(() {
                      _browserPreviewMode = !_browserPreviewMode;
                    });
                  },
                  icon: Icon(
                    _browserPreviewMode
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Collapse sidebar',
                  onPressed: () {
                    setState(() {
                      _browserCollapsed = true;
                    });
                  },
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _teamSearchController,
              decoration: const InputDecoration(
                labelText: 'Team search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Teams', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Create team',
                  onPressed: _createTeam,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
            SizedBox(
              height: 120,
              child: _loadingTeams
                  ? const Center(child: CircularProgressIndicator())
                  : filteredTeams.isEmpty
                      ? Center(
                          child: Text(
                            'No teams match.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: filteredTeams.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final entry = filteredTeams[index];
                            final selected = _selectedTeam == entry;
                            return _buildTeamCard(context, entry, selected);
                          },
                        ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Autos', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Export team PDF',
                  onPressed:
                      _selectedTeam == null ? null : _exportCurrentTeamPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'Create auto',
                  onPressed: _selectedTeam == null ? null : _createAuto,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildAutosPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutosPanel(BuildContext context) {
    final team = _selectedTeam;
    final scheme = Theme.of(context).colorScheme;

    if (team == null) {
      return const Center(child: Text('Select a team.'));
    }

    if (_autos.isEmpty) {
      return const Center(child: Text('No autos yet.'));
    }

    if (_browserPreviewMode) {
      final columns = _browserCollapsed ? 1 : 2;
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.18,
        ),
        itemCount: _autos.length,
        itemBuilder: (context, index) {
          final auto = _autos[index];
          final selected = _currentAuto?.storageId == auto.id;
          final previewAuto = auto.toPreviewAuto(team);
          final previewMatch =
              previewAuto.matchById(previewAuto.selectedMatchId);

          return Card(
            clipBehavior: Clip.antiAlias,
            color: selected
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainer,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InkWell(
                    onTap: () => _selectAuto(team, auto.id),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ObservedAutoThumbnail(
                              auto: previewAuto,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            auto.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${previewMatch.displayLabel} • 1st pass ${previewMatch.passToCenterTimes.first == null ? 'n/a' : '${previewMatch.passToCenterTimes.first!.toStringAsFixed(2)}s'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Delete auto',
                    onPressed: _isSavingAuto(team, auto.id)
                        ? null
                        : () => _deleteAuto(team, auto),
                    icon: const Icon(Icons.delete_outline),
                    color: scheme.error,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return ListView.separated(
      itemCount: _autos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final auto = _autos[index];
        final selected = _currentAuto?.storageId == auto.id;
        final previewAuto = auto.toPreviewAuto(team);
        final previewMatch = previewAuto.matchById(previewAuto.selectedMatchId);
        return Card(
          clipBehavior: Clip.antiAlias,
          color: selected
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainer,
          child: ListTile(
            selected: selected,
            title: Text(auto.name),
            subtitle: Text(
              '${previewMatch.displayLabel} • 1st pass ${previewMatch.passToCenterTimes.first == null ? 'n/a' : '${previewMatch.passToCenterTimes.first!.toStringAsFixed(2)}s'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Delete auto',
                  onPressed: _isSavingAuto(team, auto.id)
                      ? null
                      : () => _deleteAuto(team, auto),
                  icon: const Icon(Icons.delete_outline),
                  color: scheme.error,
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _selectAuto(team, auto.id),
          ),
        );
      },
    );
  }

  Widget _buildTeamCard(
    BuildContext context,
    String team,
    bool selected,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 118,
      child: Card(
        margin: EdgeInsets.zero,
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectTeam(team),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 16,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? scheme.secondary : scheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applyEditedMatchView(ObservedAuto updatedMatchView) {
    final master = _currentAuto;
    if (master == null) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? master.effectiveSelectedMatchId;
    final next = master.applyMatchView(
      matchId: activeMatchId,
      editedMatchView: updatedMatchView,
    );
    _updateAuto(next);
  }

  void _selectMatch(String? matchId) {
    if (matchId == null) {
      return;
    }
    setState(() {
      _selectedMatchId = matchId;
    });
  }

  Future<void> _addMatch() async {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final matchNumber = await _showNameDialog(
      title: 'Add Match',
      label: 'Match number',
      initialValue: '${auto.effectiveMatches().length + 1}',
    );
    if (matchNumber == null) {
      return;
    }

    final id = 'match_${DateTime.now().microsecondsSinceEpoch}';
    final newMatch = ObservedMatchObservation.blankForAuto(
      id: id,
      matchNumber: matchNumber.trim(),
      auto: auto,
    );

    _updateAuto(
      auto.copyWith(
        matches: [...auto.effectiveMatches(), newMatch],
      ),
    );
    setState(() {
      _selectedMatchId = id;
    });
  }

  void _removeSelectedMatch() {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final matches = auto.effectiveMatches();
    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    if (matches.length <= 1) {
      return;
    }

    final nextMatches =
        matches.where((match) => match.id != activeMatchId).toList();
    final nextSelected = nextMatches.first.id;
    _updateAuto(
      auto.copyWith(
        matches: nextMatches,
        selectedMatchId: nextSelected,
      ),
    );
    setState(() {
      _selectedMatchId = nextSelected;
    });
  }

  void _renameSelectedMatchNumber(String value) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(matchNumber: value.trim())
            else
              match,
        ],
      ),
    );
  }

  void _setCanMirror(bool value) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }
    _updateAuto(auto.copyWith(canMirror: value));
  }

  void _toggleMirrorRotation(int rotation, bool enabled) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final next = {...auto.mirrorRotations};
    if (enabled) {
      next.add(rotation);
    } else {
      next.remove(rotation);
    }
    _updateAuto(auto.copyWith(mirrorRotations: next.toList()..sort()));
  }

  void _setAutoType(String? value) {
    final auto = _currentAuto;
    if (auto == null || value == null) {
      return;
    }
    _updateAuto(auto.copyWith(autoType: value));
  }

  double? _parseOptionalTime(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : double.tryParse(trimmed);
  }

  void _setWaypointTimingForSelectedMatch(int index, String value) {
    final auto = _currentAuto;
    if (auto == null || index < 0) {
      return;
    }

    final parsed = _parseOptionalTime(value);
    if (parsed == null && value.trim().isNotEmpty) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(
                waypointTimings: [
                  for (int i = 0; i < match.waypointTimings.length; i++)
                    if (i == index)
                      match.waypointTimings[i].copyWith(timeSeconds: parsed)
                    else
                      match.waypointTimings[i],
                ],
              )
            else
              match,
        ],
      ),
    );
  }

  void _setMarkerTimingForSelectedMatch(String markerId, String value) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final parsed = _parseOptionalTime(value);
    if (parsed == null && value.trim().isNotEmpty) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(
                markerTimings: [
                  for (final timing in match.markerTimings)
                    if (timing.markerId == markerId)
                      timing.copyWith(timeSeconds: parsed)
                    else
                      timing,
                ],
              )
            else
              match,
        ],
      ),
    );
  }

  void _setMarkerNameForSelectedMatch(String markerId, String value) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(
                markerTimings: [
                  for (final timing in match.markerTimings)
                    if (timing.markerId == markerId)
                      timing.copyWith(name: value.trim())
                    else
                      timing,
                ],
              )
            else
              match,
        ],
      ),
    );
  }

  void _setMarkerToCenterForSelectedMatch(String markerId, bool value) {
    final auto = _currentAuto;
    if (auto == null) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(
                markerTimings: [
                  for (final timing in match.markerTimings)
                    if (timing.markerId == markerId)
                      timing.copyWith(
                        isToCenter: value,
                        passNumber: value ? (timing.passNumber ?? 1) : null,
                      )
                    else
                      timing,
                ],
              )
            else
              match,
        ],
      ),
    );
  }

  void _setMarkerPassForSelectedMatch(String markerId, int? passNumber) {
    final auto = _currentAuto;
    if (auto == null || passNumber == null) {
      return;
    }

    final activeMatchId = _selectedMatchId ?? auto.effectiveSelectedMatchId;
    _updateAuto(
      auto.copyWith(
        matches: [
          for (final match in auto.effectiveMatches())
            if (match.id == activeMatchId)
              match.copyWith(
                markerTimings: [
                  for (final timing in match.markerTimings)
                    if (timing.markerId == markerId)
                      timing.copyWith(
                        isToCenter: true,
                        passNumber: passNumber,
                      )
                    else
                      timing,
                ],
              )
            else
              match,
        ],
      ),
    );
  }

  Widget _buildMatchForms(
    BuildContext context,
    ObservedAuto auto,
    String activeMatchId,
  ) {
    return ScoutingMatchEditor(
      auto: auto,
      activeMatchId: activeMatchId,
      documentKey: auto.createdAt.isNotEmpty ? auto.createdAt : auto.storageId,
      onSelectMatch: _selectMatch,
      onAddMatch: _addMatch,
      onRemoveMatch: _removeSelectedMatch,
      onRenameMatchNumber: _renameSelectedMatchNumber,
      onSetCanMirror: _setCanMirror,
      onToggleMirrorRotation: _toggleMirrorRotation,
      onSetAutoType: _setAutoType,
      onSetWaypointTiming: _setWaypointTimingForSelectedMatch,
      onSetMarkerTiming: _setMarkerTimingForSelectedMatch,
      onSetMarkerName: _setMarkerNameForSelectedMatch,
      onSetMarkerToCenter: _setMarkerToCenterForSelectedMatch,
      onSetMarkerPass: _setMarkerPassForSelectedMatch,
    );
  }

  Widget _buildEditorPanel(BuildContext context) {
    if (_loadingAuto) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_currentAuto == null) {
      return Center(
        child: Text(
          'Select a team and auto.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final masterAuto = _currentAuto!;
    final activeMatchId =
        _selectedMatchId ?? masterAuto.effectiveSelectedMatchId;
    final editorAuto = masterAuto.viewForMatch(activeMatchId);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final editorHeight =
              min(max(constraints.maxHeight * 0.72, 520.0), 920.0);

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _autoNameController,
                          decoration: const InputDecoration(
                            labelText: 'Auto name',
                            prefixIcon: Icon(Icons.route_outlined),
                          ),
                          onChanged: (value) {
                            if (_currentAuto != null) {
                              _updateAuto(
                                _currentAuto!.copyWith(name: value),
                                dirty: true,
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _currentAuto!.fieldId,
                          decoration: const InputDecoration(
                            labelText: 'Field',
                            prefixIcon: Icon(Icons.stadium_outlined),
                          ),
                          items: [
                            for (final option
                                in ObservedFieldSpec.officialFields)
                              DropdownMenuItem(
                                value: option.id,
                                child: Text(option.label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null || _currentAuto == null) {
                              return;
                            }
                            _updateAuto(_currentAuto!.copyWith(fieldId: value));
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _exportCurrentAuto,
                        icon: const Icon(Icons.data_object_rounded),
                        label: const Text('Export JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _exportCurrentRenderJpeg,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Export JPEG'),
                      ),
                      Chip(
                        label: Text(_saveStatusLabel),
                        avatar: Icon(_saveStatusIcon, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: editorHeight,
                    child: ScoutingPathplannerEditor(
                      key: ValueKey(
                        'editor-${masterAuto.storageId}-$activeMatchId-${masterAuto.updatedAt}',
                      ),
                      auto: editorAuto,
                      onChanged: _applyEditedMatchView,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildMatchForms(context, masterAuto, activeMatchId),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
