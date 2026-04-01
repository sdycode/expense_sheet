import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/spreadsheet_sheet_kind.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_database_service.dart';
import '../services/google_drive_spreadsheet_list_service.dart';
import '../services/google_sheets_service.dart';
import '../services/spreadsheet_storage_service.dart';
import 'expenses_list_screen.dart';
import 'spreadsheet_picker_screen.dart';

/// How a spreadsheet is shown in "My Spreadsheets" sections.
enum _SheetDisplayKind {
  /// Owner-registered home / group sheet (10-column).
  homeGroup,

  /// Owner-registered personal sheet (10 columns; links to home id).
  personal,

  /// Sheet shared with the current user (viewer / collaborator).
  sharedWithMe,
}

class SpreadsheetSelectionScreen extends StatefulWidget {
  final GoogleSheetsService sheetsService;

  const SpreadsheetSelectionScreen({super.key, required this.sheetsService});

  @override
  State<SpreadsheetSelectionScreen> createState() =>
      _SpreadsheetSelectionScreenState();
}

class _SpreadsheetSelectionScreenState
    extends State<SpreadsheetSelectionScreen> {
  final SpreadsheetStorageService _storageService = SpreadsheetStorageService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirebaseDatabaseService _firebaseDb = FirebaseDatabaseService();

  List<SpreadsheetInfo> _homeSheets = [];
  List<SpreadsheetInfo> _personalSheets = [];
  List<SpreadsheetInfo> _sharedSheets = [];
  /// Spreadsheets shared via Drive, not owned by user, not saved in app
  /// (compact horizontal row under Shared / group; includes non-compatible).
  List<DriveSpreadsheetRef> _driveSharedOthers = [];
  /// Local sheet ids that also appear in "shared with me" (badge only).
  Set<String> _idsAlsoSharedWithMe = {};
  /// Full-screen loading shown only on first open before cache is shown.
  bool _isLoading = true;
  /// Thin progress bar while background network refresh is running.
  bool _isRefreshing = false;
  String? _activeCommonId;
  String? _activePersonalId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _showCachedThenRefresh();
  }

  /// Pull current document title from Google Sheets (source of truth for names).
  Future<SpreadsheetInfo> _refreshSheetTitle(
    SpreadsheetInfo s, {
    required bool persistToLocalPrefs,
  }) async {
    try {
      final title =
          await widget.sheetsService.getSpreadsheetNameWithReauthorize(
        s.id,
        () async {
          final token = await _authService.getAccessToken(forceRefresh: true);
          if (token == null || token.isEmpty) {
            throw StateError('No Google access token after refresh');
          }
          await widget.sheetsService.initializeSheetsApiWithToken(token);
        },
      );
      if (title != null && title.trim().isNotEmpty) {
        final trimmed = title.trim();
        if (trimmed != (s.name ?? '')) {
          final updated = SpreadsheetInfo(
            id: s.id,
            name: trimmed,
            addedDate: s.addedDate,
            sheetKind: s.sheetKind,
          );
          if (persistToLocalPrefs) {
            await _storageService.saveSpreadsheet(updated);
          }
          return updated;
        }
      }
    } catch (e) {
      debugPrint('SpreadsheetSelectionScreen: title refresh ${s.id}: $e');
    }
    return s;
  }

  /// Phase 1: instantly show cached spreadsheets from local prefs, then kick
  /// off background network refresh.
  Future<void> _showCachedThenRefresh() async {
    await _storageService.migrateLegacyActiveSheetIdIfNeeded();
    final activeCommon = await _storageService.getActiveCommonSheetId();
    final activePersonal = await _storageService.getActivePersonalSheetId();
    final localSpreadsheets = await _storageService.getSavedSpreadsheets();

    _applyLocalData(
      locals: localSpreadsheets,
      shared: const [],
      driveOthers: const [],
      activeCommon: activeCommon,
      activePersonal: activePersonal,
    );
    if (mounted) setState(() => _isLoading = false);

    // Phase 2 runs in the background; UI already visible.
    unawaited(_refreshFromNetwork());
  }

  /// Phase 2: fetch Firebase, refresh titles, fetch Drive list, then update
  /// the UI only if something changed.
  Future<void> _refreshFromNetwork() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    try {
      final currentUserEmail = _authService.currentUser?.email;
      var localSpreadsheets = await _storageService.getSavedSpreadsheets();

      // Run Firebase and token fetch in parallel.
      final results = await Future.wait([
        currentUserEmail != null
            ? _firebaseDb.getSharedSpreadsheets(currentUserEmail)
            : Future.value(<Map<String, String?>>[]),
        _authService.getAccessToken(forceRefresh: true),
      ]);

      final sharedRaw = results[0] as List<Map<String, String?>>;
      final token = results[1] as String?;

      final sharedSpreadsheetsInfo = sharedRaw
          .map(
            (s) => SpreadsheetInfo(
              id: s['id']!,
              name: s['name'],
              addedDate: DateTime.now(),
            ),
          )
          .toList();

      if (token != null && token.isNotEmpty) {
        try {
          await widget.sheetsService.initializeSheetsApiWithToken(token);

          // Fetch Drive list, refresh local+shared titles, all in parallel.
          final driveSvc = GoogleDriveSpreadsheetListService();

          final refreshedLocalsFuture = Future.wait(
            localSpreadsheets.map(
              (s) => _refreshSheetTitle(s, persistToLocalPrefs: true),
            ),
          );
          final refreshedSharedFuture = Future.wait(
            sharedSpreadsheetsInfo.map(
              (s) => _refreshSheetTitle(s, persistToLocalPrefs: false),
            ),
          );
          final driveAllFuture = driveSvc
              .listSpreadsheets(ownedByMeOnly: false)
              .catchError((e) {
            debugPrint(
              'SpreadsheetSelectionScreen: Drive list error: $e',
            );
            return <DriveSpreadsheetRef>[];
          });

          final allResults = await Future.wait([
            refreshedLocalsFuture,
            refreshedSharedFuture,
            driveAllFuture,
          ]);

          final refreshedLocals = allResults[0] as List<SpreadsheetInfo>;
          final refreshedShared = allResults[1] as List<SpreadsheetInfo>;
          final driveAll = allResults[2] as List<DriveSpreadsheetRef>;

          final driveIds = driveAll.map((r) => r.id).toSet();
          final localIds = refreshedLocals.map((s) => s.id).toSet();

          // Mark any saved sheet that is no longer visible on Drive.
          localSpreadsheets = refreshedLocals.map((s) {
            final gone = driveIds.isNotEmpty && !driveIds.contains(s.id);
            if (gone) {
              debugPrint(
                'SpreadsheetSelectionScreen: sheet not on Drive '
                '(deleted/access removed): ${s.id} (${s.name})',
              );
            }
            return gone ? s.copyWith(unavailable: true) : s;
          }).toList();

          // Build Drive-shared-others strip (not owned, not local).
          final candidates = driveAll
              .where((r) => !r.ownedByMe && !localIds.contains(r.id))
              .toList();
          final compatFutures = candidates.map((r) async {
            try {
              final ok =
                  await widget.sheetsService.isCompatibleExpenseSheet(r.id);
              debugPrint(
                'SpreadsheetSelectionScreen: drive-shared compat '
                '${r.id} (${r.name}) → $ok',
              );
              return r.copyWith(compatible: ok);
            } catch (e) {
              debugPrint(
                'SpreadsheetSelectionScreen: drive-shared compat error '
                '${r.id} (${r.name}): $e',
              );
              return r.copyWith(compatible: false);
            }
          });
          final driveOthers = await Future.wait(compatFutures)
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          var activeCommon = await _storageService.getActiveCommonSheetId();
          var activePersonal = await _storageService.getActivePersonalSheetId();

          // Auto-deselect active sheet if it became unavailable.
          final unavailableIds = localSpreadsheets
              .where((s) => s.unavailable)
              .map((s) => s.id)
              .toSet();

          if (activeCommon != null && unavailableIds.contains(activeCommon)) {
            debugPrint(
              'SpreadsheetSelectionScreen: active common sheet '
              '$activeCommon is unavailable — clearing active selection',
            );
            await _storageService.clearActiveCommonSheetId();
            // Pick the next available common sheet.
            final next = localSpreadsheets.firstWhere(
              (s) => s.sheetKind != SpreadsheetSheetKind.personal.dbValue && !s.unavailable,
              orElse: () => localSpreadsheets.firstWhere(
                (s) => !s.unavailable,
                orElse: () => localSpreadsheets.first,
              ),
            );
            if (!next.unavailable) {
              await _storageService.setActiveCommonSheetId(next.id);
              activeCommon = next.id;
            } else {
              activeCommon = null;
            }
          }

          if (activePersonal != null && unavailableIds.contains(activePersonal)) {
            debugPrint(
              'SpreadsheetSelectionScreen: active personal sheet '
              '$activePersonal is unavailable — clearing active selection',
            );
            await _storageService.clearActivePersonalSheetId();
            final next = localSpreadsheets.firstWhere(
              (s) => s.sheetKind == SpreadsheetSheetKind.personal.dbValue && !s.unavailable,
              orElse: () => SpreadsheetInfo(id: '', name: null, addedDate: DateTime.now(), unavailable: true),
            );
            activePersonal = next.unavailable ? null : next.id;
          }

          if (!mounted) return;
          _applyLocalData(
            locals: localSpreadsheets,
            shared: refreshedShared,
            driveOthers: driveOthers,
            activeCommon: activeCommon,
            activePersonal: activePersonal,
          );

          // Notify user once if their active sheet was removed.
          if (unavailableIds.isNotEmpty && mounted) {
            final names = localSpreadsheets
                .where((s) => s.unavailable)
                .map((s) => s.name ?? s.id)
                .join(', ');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Some sheets are no longer accessible: $names',
                ),
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.orange.shade800,
              ),
            );
          }
        } catch (e) {
          debugPrint(
            'SpreadsheetSelectionScreen: background refresh error: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('SpreadsheetSelectionScreen: _refreshFromNetwork: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Convenience called from the refresh button; shows full spinner.
  Future<void> _loadSpreadsheets() async {
    if (mounted) setState(() => _isLoading = true);
    await _showCachedThenRefresh();
  }

  /// Splits local + shared lists into sections and calls [setState].
  void _applyLocalData({
    required List<SpreadsheetInfo> locals,
    required List<SpreadsheetInfo> shared,
    required List<DriveSpreadsheetRef> driveOthers,
    required String? activeCommon,
    required String? activePersonal,
  }) {
    final localIds = locals.map((s) => s.id).toSet();
    final sharedIds = shared.map((s) => s.id).toSet();
    final alsoShared = localIds.intersection(sharedIds);

    final home = <SpreadsheetInfo>[];
    final personal = <SpreadsheetInfo>[];
    for (final s in locals) {
      if (s.sheetKind == SpreadsheetSheetKind.personal.dbValue) {
        personal.add(s);
      } else {
        home.add(s);
      }
    }

    void sortByName(List<SpreadsheetInfo> list) {
      list.sort(
        (a, b) => (a.name ?? a.id).toLowerCase().compareTo(
              (b.name ?? b.id).toLowerCase(),
            ),
      );
    }

    sortByName(home);
    sortByName(personal);

    final sharedOnly = shared.where((s) => !localIds.contains(s.id)).toList();
    sortByName(sharedOnly);

    if (!mounted) return;
    setState(() {
      _homeSheets = home;
      _personalSheets = personal;
      _sharedSheets = sharedOnly;
      _driveSharedOthers = driveOthers;
      _idsAlsoSharedWithMe = alsoShared;
      _activeCommonId = activeCommon;
      _activePersonalId = activePersonal;
    });
  }

  Future<void> _navigateToExpenses(
    SpreadsheetInfo spreadsheet,
    _SheetDisplayKind displayKind,
  ) async {
    final personalLayout = displayKind == _SheetDisplayKind.personal;
    if (personalLayout) {
      await _storageService.setActivePersonalSheetId(spreadsheet.id);
    } else {
      await _storageService.setActiveSpreadsheetId(spreadsheet.id);
    }
    if (!mounted) return;
    setState(() {
      if (personalLayout) {
        _activePersonalId = spreadsheet.id;
      } else {
        _activeCommonId = spreadsheet.id;
      }
    });
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpensesListScreen(
          sheetsService: widget.sheetsService,
          spreadsheetId: spreadsheet.id,
          personalLayout: personalLayout,
        ),
      ),
    );
  }

  Future<void> _openDriveSharedSpreadsheet(DriveSpreadsheetRef r) async {
    if (r.compatible != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${r.name}" does not match the expense layout (columns A–J). '
              'You can open it but expenses cannot be tracked there.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Save to local prefs and set as active shared sheet so expenses go here.
    final info = SpreadsheetInfo(
      id: r.id,
      name: r.name,
      addedDate: r.modifiedTime ?? DateTime.now(),
      sheetKind: SpreadsheetSheetKind.common.dbValue,
    );
    try {
      await _storageService.saveSpreadsheet(info);
      await _storageService.setActiveCommonSheetId(r.id);
    } catch (e) {
      debugPrint('SpreadsheetSelectionScreen: save drive-shared sheet: $e');
    }
    if (!mounted) return;
    setState(() => _activeCommonId = r.id);
    _navigateToExpenses(info, _SheetDisplayKind.homeGroup);
  }

  Widget _driveSharedOthersStrip(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Text(
                'Shared with you on Drive',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              if (_isRefreshing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Tap a compatible sheet to set it as your active shared sheet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _driveSharedOthers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final r = _driveSharedOthers[i];
              final isActive = r.id == _activeCommonId;
              return _CompactDriveSharedCard(
                ref: r,
                isActive: isActive,
                onTap: () => _openDriveSharedSpreadsheet(r),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  bool _isSheetHighlighted(SpreadsheetInfo s) =>
      s.id == _activeCommonId || s.id == _activePersonalId;

  Future<void> _openDrivePicker() async {
    final token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in from the expense screen, then try again.'),
          ),
        );
      }
      return;
    }
    await widget.sheetsService.initializeSheetsApiWithToken(token);

    final pickedKind = await showModalBottomSheet<SpreadsheetPickerPurpose>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Browse shared / group sheets'),
              subtitle: const Text('10 columns · shared expenses'),
              onTap: () =>
                  Navigator.pop(ctx, SpreadsheetPickerPurpose.common),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Browse personal sheets'),
              subtitle: const Text('10 columns · owner only · links shared sheet id'),
              onTap: () =>
                  Navigator.pop(ctx, SpreadsheetPickerPurpose.personal),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pickedKind == null) return;

    final r = await Navigator.push<SpreadsheetPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) => SpreadsheetPickerScreen(
          sheetsService: widget.sheetsService,
          purpose: pickedKind,
        ),
      ),
    );
    if (!mounted || r == null) return;
    if (pickedKind == SpreadsheetPickerPurpose.common) {
      await _storageService.setActiveCommonSheetId(r.spreadsheetId);
    } else {
      await _storageService.setActivePersonalSheetId(r.spreadsheetId);
    }
    await _loadSpreadsheets();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: ${r.name ?? r.spreadsheetId}')),
      );
    }
  }

  Future<void> _createNewSheet(SpreadsheetSheetKind kind) async {
    if (_creating) return;
    final email = _authService.currentUser?.email?.trim();
    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in from the expense screen first.')),
        );
      }
      return;
    }

    final token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get Google access. Sign in again.'),
          ),
        );
      }
      return;
    }

    // --- Ask the user for a name before creating the sheet ---
    final defaultName = kind == SpreadsheetSheetKind.personal
        ? 'Personal expenses'
        : 'Shared / group expenses';
    final existingNames = [
      ..._homeSheets.map((s) => (s.name ?? '').toLowerCase()),
      ..._personalSheets.map((s) => (s.name ?? '').toLowerCase()),
    ];
    final title = await _promptSheetName(
      defaultName: defaultName,
      existingNames: existingNames,
    );
    if (title == null) return; // user cancelled

    setState(() => _creating = true);
    try {
      await widget.sheetsService.initializeSheetsApiWithToken(token);
      final id = await widget.sheetsService.createBlankSpreadsheet(title: title);
      if (id == null || id.isEmpty) {
        throw Exception('No spreadsheet id returned');
      }

      // Write the correct header row immediately so the sheet is ready to use.
      await widget.sheetsService.writeHeaders(
        id,
        personalLayout: kind == SpreadsheetSheetKind.personal,
      );

      await _firebaseDb.registerSpreadsheetOwnership(
        ownerEmail: email,
        spreadsheetId: id,
        displayName: title,
        sheetKind: kind,
      );
      await _storageService.saveSpreadsheet(
        SpreadsheetInfo(
          id: id,
          name: title,
          addedDate: DateTime.now(),
          sheetKind: kind.dbValue,
        ),
      );
      if (kind == SpreadsheetSheetKind.common) {
        await _storageService.setActiveCommonSheetId(id);
      } else {
        await _storageService.setActivePersonalSheetId(id);
      }
      await _loadSpreadsheets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created "$title"'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('Create sheet error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create spreadsheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Shows a dialog asking the user for a spreadsheet name.
  /// Returns the entered name, or null if the user cancelled.
  Future<String?> _promptSheetName({
    required String defaultName,
    required List<String> existingNames,
  }) async {
    final controller = TextEditingController(text: defaultName);
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDupe = existingNames.contains(
              controller.text.trim().toLowerCase(),
            );
            return AlertDialog(
              title: const Text('Name your spreadsheet'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Spreadsheet name',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a name.';
                        }
                        return null;
                      },
                    ),
                    if (isDupe) ...[
                      const SizedBox(height: 8),
                      Text(
                        'A sheet with this name already exists in the app.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(ctx, controller.text.trim());
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySectionHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _createActionsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a spreadsheet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _creating
                    ? null
                    : () => _createNewSheet(SpreadsheetSheetKind.common),
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add, size: 20),
                label: const Text('New shared sheet'),
              ),
              FilledButton.tonalIcon(
                onPressed: _creating
                    ? null
                    : () => _createNewSheet(SpreadsheetSheetKind.personal),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New personal sheet'),
              ),
              OutlinedButton.icon(
                onPressed: _creating ? null : _openDrivePicker,
                icon: const Icon(Icons.cloud_outlined, size: 20),
                label: const Text('Browse Drive'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheetGrid(
    List<SpreadsheetInfo> items,
    _SheetDisplayKind displayKind, {
    required String emptyHint,
  }) {
    if (items.isEmpty) return _emptySectionHint(emptyHint);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final spreadsheet = items[index];
        final alsoShared = displayKind != _SheetDisplayKind.sharedWithMe &&
            _idsAlsoSharedWithMe.contains(spreadsheet.id);
        return _SpreadsheetCard(
          spreadsheet: spreadsheet,
          index: index,
          displayKind: displayKind,
          isActive: _isSheetHighlighted(spreadsheet),
          showAlsoSharedBadge: alsoShared,
          onTap: () => _navigateToExpenses(spreadsheet, displayKind),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAny = _homeSheets.isNotEmpty ||
        _personalSheets.isNotEmpty ||
        _sharedSheets.isNotEmpty ||
        _driveSharedOthers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Spreadsheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create new sheet',
            onPressed: _creating
                ? null
                : () {
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.groups_outlined),
                              title: const Text('New shared / group sheet'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewSheet(SpreadsheetSheetKind.common);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: const Text('New personal sheet'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewSheet(SpreadsheetSheetKind.personal);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            onPressed: _creating ? null : _openDrivePicker,
            tooltip: 'Browse Google Drive',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSpreadsheets,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isRefreshing)
                  const LinearProgressIndicator(minHeight: 3),
                Expanded(
                  child: ListView(
              children: [
                _createActionsBar(),
                if (!hasAny) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'No sheets saved yet. Create a new one, or browse Drive '
                      'to add a compatible spreadsheet to the app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _sectionHeader(
                  icon: Icons.groups_outlined,
                  title: 'Shared / group spreadsheets',
                  subtitle:
                      'Shared or household expenses · 10 columns (includes Paid by)',
                ),
                _sheetGrid(
                  _homeSheets,
                  _SheetDisplayKind.homeGroup,
                  emptyHint: 'None — use New shared sheet or Browse Drive',
                ),
                if (_driveSharedOthers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _driveSharedOthersStrip(context),
                ],
                _sectionHeader(
                  icon: Icons.person_outline,
                  title: 'Personal spreadsheets',
                  subtitle:
                      'Only you (owner) can add rows · column J = shared sheet id',
                ),
                _sheetGrid(
                  _personalSheets,
                  _SheetDisplayKind.personal,
                  emptyHint: 'None — optional. Use New personal sheet or Browse Drive',
                ),
                _sectionHeader(
                  icon: Icons.group_outlined,
                  title: 'Shared with you',
                  subtitle:
                      'Sheets others invited you to · opens as shared layout',
                ),
                _sheetGrid(
                  _sharedSheets,
                  _SheetDisplayKind.sharedWithMe,
                  emptyHint:
                      'No extra shared sheets, or they are already listed above',
                ),
                const SizedBox(height: 32),
              ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SpreadsheetCard extends StatelessWidget {
  final SpreadsheetInfo spreadsheet;
  final int index;
  final _SheetDisplayKind displayKind;
  final bool isActive;
  final bool showAlsoSharedBadge;
  final VoidCallback onTap;

  const _SpreadsheetCard({
    required this.spreadsheet,
    required this.index,
    required this.displayKind,
    this.isActive = false,
    this.showAlsoSharedBadge = false,
    required this.onTap,
  });

  String get _kindLabel {
    switch (displayKind) {
      case _SheetDisplayKind.homeGroup:
        return 'Shared / group';
      case _SheetDisplayKind.personal:
        return 'Personal';
      case _SheetDisplayKind.sharedWithMe:
        return 'Shared with you';
    }
  }

  Color _chipColor(ThemeData theme) {
    switch (displayKind) {
      case _SheetDisplayKind.homeGroup:
        return theme.colorScheme.primaryContainer;
      case _SheetDisplayKind.personal:
        return theme.colorScheme.tertiaryContainer;
      case _SheetDisplayKind.sharedWithMe:
        return theme.colorScheme.secondaryContainer;
    }
  }

  Color _chipFg(ThemeData theme) {
    switch (displayKind) {
      case _SheetDisplayKind.homeGroup:
        return theme.colorScheme.onPrimaryContainer;
      case _SheetDisplayKind.personal:
        return theme.colorScheme.onTertiaryContainer;
      case _SheetDisplayKind.sharedWithMe:
        return theme.colorScheme.onSecondaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = spreadsheet.name ?? 'Spreadsheet ${index + 1}';
    final dateAdded = DateFormat('MMM dd, yyyy').format(spreadsheet.addedDate);
    final theme = Theme.of(context);
    final isUnavailable = spreadsheet.unavailable;

    final cardBorderColor = isUnavailable
        ? theme.colorScheme.error
        : isActive
            ? theme.colorScheme.primary
            : Colors.transparent;

    return Opacity(
      opacity: isUnavailable ? 0.65 : 1.0,
      child: Card(
        elevation: isActive ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: cardBorderColor,
            width: (isActive || isUnavailable) ? 2 : 0,
          ),
        ),
        child: InkWell(
          // Block tapping when unavailable.
          onTap: isUnavailable ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isUnavailable
                          ? Icons.cloud_off
                          : displayKind == _SheetDisplayKind.personal
                              ? Icons.person
                              : displayKind == _SheetDisplayKind.sharedWithMe
                                  ? Icons.folder_shared_outlined
                                  : Icons.groups_outlined,
                      size: 28,
                      color: isUnavailable
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    if (isActive && !isUnavailable) ...[
                      const Spacer(),
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (isUnavailable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Deleted / no access',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _chipColor(theme),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _kindLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _chipFg(theme),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showAlsoSharedBadge) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Also in Shared with you',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 6),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isUnavailable
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                        : null,
                    decoration: isUnavailable
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  dateAdded,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ID: ${spreadsheet.id.length > 8 ? "${spreadsheet.id.substring(0, 8)}…" : spreadsheet.id}',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[500],
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isUnavailable)
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: Colors.grey[400],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small horizontal card for Drive spreadsheets shared with the user (not owned).
class _CompactDriveSharedCard extends StatelessWidget {
  const _CompactDriveSharedCard({
    required this.ref,
    required this.onTap,
    this.isActive = false,
  });

  final DriveSpreadsheetRef ref;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompat = ref.compatible;
    final compatChecked = isCompat != null;

    // Compatible = green accent; incompatible = muted; unchecked = neutral.
    final Color badgeBg;
    final Color badgeFg;
    final String badgeLabel;
    if (!compatChecked) {
      badgeBg = theme.colorScheme.surfaceContainerHighest;
      badgeFg = theme.colorScheme.onSurfaceVariant;
      badgeLabel = 'Checking…';
    } else if (isCompat == true) {
      badgeBg = Colors.green.shade100;
      badgeFg = Colors.green.shade800;
      badgeLabel = 'Compatible';
    } else {
      badgeBg = theme.colorScheme.errorContainer;
      badgeFg = theme.colorScheme.onErrorContainer;
      badgeLabel = 'Incompatible';
    }

    final borderColor =
        isActive ? theme.colorScheme.primary : Colors.transparent;

    return Material(
      color: isActive
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isActive ? 2 : 0),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 136,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_shared_outlined,
                      size: 16,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    ref.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                // Compatibility badge.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: badgeFg,
                      letterSpacing: 0.2,
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
}
