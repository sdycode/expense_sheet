import 'package:MoneyTracker/models/spreadsheet_sheet_kind.dart';
import 'package:MoneyTracker/services/services_module.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Whether the picker targets home/common (10-column) or personal (10-column) sheets.
enum SpreadsheetPickerPurpose {
  common,
  personal,
}

/// Returned when the user picks a registered sheet for the expense tracker.
class SpreadsheetPickerResult {
  SpreadsheetPickerResult({
    required this.spreadsheetId,
    this.name,
  });

  final String spreadsheetId;
  final String? name;
}

class _SheetPickItem {
  _SheetPickItem({
    required this.id,
    required this.name,
    required this.ownedByMe,
    this.driveModified,
    this.compatible = true,
  });

  final String id;
  final String name;
  final bool ownedByMe;
  final DateTime? driveModified;
  final bool compatible;
}

/// Browse Google Drive spreadsheets, filter by app format, split by Firebase registration.
class SpreadsheetPickerScreen extends StatefulWidget {
  const SpreadsheetPickerScreen({
    super.key,
    required this.sheetsService,
    this.purpose = SpreadsheetPickerPurpose.common,
  });

  final GoogleSheetsService sheetsService;
  final SpreadsheetPickerPurpose purpose;

  @override
  State<SpreadsheetPickerScreen> createState() =>
      _SpreadsheetPickerScreenState();
}

class _SpreadsheetPickerScreenState extends State<SpreadsheetPickerScreen> {
  final _driveList = GoogleDriveSpreadsheetListService();
  final _storage = SpreadsheetStorageService();
  final _fb = FirebaseDatabaseService();

  bool _loading = true;
  String? _error;
  final List<_SheetPickItem> _working = [];
  final List<_SheetPickItem> _addToApp = [];
  final List<_SheetPickItem> _sharedCompatible = [];
  String? _activeId;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userEmail = FirebaseAuth.instance.currentUser?.email?.trim();
      final isPersonalPicker =
          widget.purpose == SpreadsheetPickerPurpose.personal;
      _activeId = isPersonalPicker
          ? await _storage.getActivePersonalSheetId()
          : await _storage.getActiveCommonSheetId();

      final ownedRemote = userEmail != null && userEmail.isNotEmpty
          ? await _fb.getOwnedSpreadsheetsRemote(userEmail)
          : <Map<String, String>>[];
      final ownedIds =
          ownedRemote.map((m) => m['id']!.trim()).toSet();

      final driveFiles = await _driveList.listSpreadsheets(ownedByMeOnly: false);
      final byId = {for (final d in driveFiles) d.id: d};

      final compatCommon = <String, bool>{};
      final compatPersonal = <String, bool>{};
      for (final d in driveFiles) {
        try {
          compatCommon[d.id] =
              await widget.sheetsService.isCompatibleExpenseSheet(d.id);
        } catch (_) {
          compatCommon[d.id] = false;
        }
        try {
          compatPersonal[d.id] =
              await widget.sheetsService.isCompatiblePersonalExpenseSheet(d.id);
        } catch (_) {
          compatPersonal[d.id] = false;
        }
      }

      bool rowMatchesPurpose(Map<String, String> row) {
        final sk = row['sheetKind'] ?? SpreadsheetSheetKind.common.dbValue;
        if (isPersonalPicker) return sk == SpreadsheetSheetKind.personal.dbValue;
        return sk != SpreadsheetSheetKind.personal.dbValue;
      }

      bool driveCompat(String id) =>
          isPersonalPicker ? (compatPersonal[id] == true) : (compatCommon[id] == true);

      final working = <_SheetPickItem>[];
      for (final row in ownedRemote) {
        if (!rowMatchesPurpose(row)) continue;
        final id = row['id']!.trim();
        final name = row['name']?.trim().isNotEmpty == true
            ? row['name']!.trim()
            : 'Spreadsheet';
        final ref = byId[id];
        final isCompat = ref == null ? true : driveCompat(id);
        working.add(
          _SheetPickItem(
            id: id,
            name: name,
            ownedByMe: ref?.ownedByMe ?? true,
            driveModified: ref?.modifiedTime,
            compatible: isCompat,
          ),
        );
      }

      final addToApp = <_SheetPickItem>[];
      final shared = <_SheetPickItem>[];
      for (final d in driveFiles) {
        if (ownedIds.contains(d.id)) continue;
        if (!driveCompat(d.id)) continue;
        if (d.ownedByMe) {
          addToApp.add(
            _SheetPickItem(
              id: d.id,
              name: d.name,
              ownedByMe: true,
              driveModified: d.modifiedTime,
              compatible: true,
            ),
          );
        } else {
          shared.add(
            _SheetPickItem(
              id: d.id,
              name: d.name,
              ownedByMe: false,
              driveModified: d.modifiedTime,
              compatible: true,
            ),
          );
        }
      }

      addToApp.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      shared.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      working.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _working
          ..clear()
          ..addAll(working);
        _addToApp
          ..clear()
          ..addAll(addToApp);
        _sharedCompatible
          ..clear()
          ..addAll(shared);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectWorking(_SheetPickItem item) async {
    if (widget.purpose == SpreadsheetPickerPurpose.personal) {
      await _storage.setActivePersonalSheetId(item.id);
    } else {
      await _storage.setActiveCommonSheetId(item.id);
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      SpreadsheetPickerResult(spreadsheetId: item.id, name: item.name),
    );
  }

  Future<void> _addToFirebase(_SheetPickItem item) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email?.trim();
    if (userEmail == null || userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to add a spreadsheet.')),
      );
      return;
    }
    if (!item.ownedByMe) return;

    setState(() => _adding.add(item.id));
    try {
      final kind = widget.purpose == SpreadsheetPickerPurpose.personal
          ? SpreadsheetSheetKind.personal
          : SpreadsheetSheetKind.common;
      await _fb.registerSpreadsheetOwnership(
        ownerEmail: userEmail,
        spreadsheetId: item.id,
        displayName: item.name,
        sheetKind: kind,
      );
      final existing = await _storage.getSpreadsheet(item.id);
      await _storage.saveSpreadsheet(
        SpreadsheetInfo(
          id: item.id,
          name: item.name,
          addedDate: existing?.addedDate ?? DateTime.now(),
          sheetKind: kind.dbValue,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${item.name}" to the app.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not add: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _adding.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isPersonal = widget.purpose == SpreadsheetPickerPurpose.personal;
    final title = isPersonal ? 'Personal spreadsheets' : 'Shared spreadsheets';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          isPersonal
                              ? 'Personal sheets use 10 columns on Sheet1 (no Paid By; '
                                  'last column = linked shared sheet id). '
                                  'Working lists sheets registered as personal. '
                                  'Tap one to set your active personal sheet.'
                              : 'Shared sheets use 10 columns on Sheet1 (includes Paid By). '
                                  'Working lists sheets registered as shared. '
                                  'Tap one to set your active shared sheet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    ..._sectionSlivers(
                      context,
                      title: 'Working sheets',
                      subtitle:
                          'Registered in the app — tap to select for editing',
                      items: _working,
                      selectable: true,
                    ),
                    ..._sectionSlivers(
                      context,
                      title: 'Compatible — not in app yet',
                      subtitle:
                          'You own these — add to the app, then they appear above',
                      items: _addToApp,
                      selectable: false,
                      showAdd: true,
                    ),
                    ..._sectionSlivers(
                      context,
                      title: 'Shared with you (compatible)',
                      subtitle:
                          'Ask the owner to register the sheet in the app',
                      items: _sharedCompatible,
                      selectable: false,
                      showAdd: false,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
    );
  }

  List<Widget> _sectionSlivers(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<_SheetPickItem> items,
    required bool selectable,
    bool showAdd = false,
  }) {
    if (items.isEmpty) return [];

    final theme = Theme.of(context);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              final isActive = item.id == _activeId;
              return _PickCard(
                item: item,
                isActive: isActive,
                selectable: selectable,
                showAdd: showAdd,
                adding: _adding.contains(item.id),
                onSelect:
                    selectable ? () => _selectWorking(item) : null,
                onAdd: showAdd && item.ownedByMe
                    ? () => _addToFirebase(item)
                    : null,
              );
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.item,
    required this.isActive,
    required this.selectable,
    required this.showAdd,
    required this.adding,
    this.onSelect,
    this.onAdd,
  });

  final _SheetPickItem item;
  final bool isActive;
  final bool selectable;
  final bool showAdd;
  final bool adding;
  final VoidCallback? onSelect;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.35);
    final width = isActive ? 2.5 : 1.0;

    String? modified;
    if (item.driveModified != null) {
      modified = DateFormat('MMM d, yyyy').format(item.driveModified!);
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectable ? onSelect : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: width),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.table_chart,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                  if (isActive) ...[
                    const Spacer(),
                    Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!item.compatible)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Header mismatch on Sheet1',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (modified != null)
                Text(
                  modified,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                item.id,
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (showAdd && onAdd != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: adding ? null : onAdd,
                    child: adding
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add to app'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
