import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/spreadsheet_sheet_kind.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_database_service.dart';
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
  /// Local sheet ids that also appear in "shared with me" (badge only).
  Set<String> _idsAlsoSharedWithMe = {};
  bool _isLoading = true;
  String? _activeCommonId;
  String? _activePersonalId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadSpreadsheets();
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

  Future<void> _loadSpreadsheets() async {
    setState(() => _isLoading = true);
    try {
      await _storageService.migrateLegacyActiveSheetIdIfNeeded();
      final activeCommon = await _storageService.getActiveCommonSheetId();
      final activePersonal = await _storageService.getActivePersonalSheetId();
      var localSpreadsheets = await _storageService.getSavedSpreadsheets();

      final sharedSpreadsheetsInfo = <SpreadsheetInfo>[];
      final currentUserEmail = _authService.currentUser?.email;
      if (currentUserEmail != null) {
        final sharedSheets = await _firebaseDb.getSharedSpreadsheets(
          currentUserEmail,
        );
        for (final sheet in sharedSheets) {
          sharedSpreadsheetsInfo.add(
            SpreadsheetInfo(
              id: sheet['id']!,
              name: sheet['name'],
              addedDate: DateTime.now(),
            ),
          );
        }
      }

      // Names in prefs / Firebase are stale if the user renamed the file in Drive.
      final token = await _authService.getAccessToken(forceRefresh: true);
      if (token != null && token.isNotEmpty) {
        try {
          await widget.sheetsService.initializeSheetsApiWithToken(token);
          final refreshedLocals = <SpreadsheetInfo>[];
          for (final s in localSpreadsheets) {
            refreshedLocals.add(
              await _refreshSheetTitle(s, persistToLocalPrefs: true),
            );
          }
          localSpreadsheets = refreshedLocals;

          for (var i = 0; i < sharedSpreadsheetsInfo.length; i++) {
            sharedSpreadsheetsInfo[i] = await _refreshSheetTitle(
              sharedSpreadsheetsInfo[i],
              persistToLocalPrefs: false,
            );
          }
        } catch (e) {
          debugPrint('SpreadsheetSelectionScreen: Sheets init for title refresh: $e');
        }
      }

      final localIds = localSpreadsheets.map((s) => s.id).toSet();

      final sharedIds = sharedSpreadsheetsInfo.map((s) => s.id).toSet();
      _idsAlsoSharedWithMe = localIds.intersection(sharedIds);

      final home = <SpreadsheetInfo>[];
      final personal = <SpreadsheetInfo>[];
      for (final s in localSpreadsheets) {
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

      final sharedOnly = sharedSpreadsheetsInfo
          .where((s) => !localIds.contains(s.id))
          .toList();
      sortByName(sharedOnly);

      setState(() {
        _homeSheets = home;
        _personalSheets = personal;
        _sharedSheets = sharedOnly;
        _activeCommonId = activeCommon;
        _activePersonalId = activePersonal;
      });
    } catch (e) {
      debugPrint('Error loading spreadsheets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading spreadsheets: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    setState(() => _creating = true);
    try {
      await widget.sheetsService.initializeSheetsApiWithToken(token);
      final title = kind == SpreadsheetSheetKind.personal
          ? 'Personal expenses'
          : 'Shared / group expenses';
      final id = await widget.sheetsService.createBlankSpreadsheet(title: title);
      if (id == null || id.isEmpty) {
        throw Exception('No spreadsheet id returned');
      }

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
            content: Text('Created "${title}"'),
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
        _sharedSheets.isNotEmpty;

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
          : ListView(
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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

    return Card(
      elevation: isActive ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    displayKind == _SheetDisplayKind.personal
                        ? Icons.person
                        : displayKind == _SheetDisplayKind.sharedWithMe
                            ? Icons.folder_shared_outlined
                            : Icons.groups_outlined,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                  if (isActive) ...[
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              const SizedBox(height: 6),
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
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
    );
  }
}
