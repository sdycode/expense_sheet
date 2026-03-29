import 'package:MoneyTracker/services/services_module.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum _MemberDriveUiStatus {
  owner,
  accepted,
  pending,
  rejected,
  appOnly,
  /// Drive list failed — do not infer rejected.
  driveUnknown,
}

bool _dynBool(dynamic v) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return false;
}

bool? _dynBoolNullable(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return null;
}

_MemberDriveUiStatus _statusForMember(
  Map<String, dynamic> member,
  Set<String> driveWriterEmails,
  bool driveLookupOk,
) {
  final role = member['role']?.toString() ?? '';
  final email =
      member['email']?.toString().trim().toLowerCase() ?? '';
  if (role == 'owner') return _MemberDriveUiStatus.owner;

  final grant = _dynBoolNullable(member['driveLastGrantSuccess']);
  if (!driveLookupOk) {
    if (grant == false) return _MemberDriveUiStatus.appOnly;
    return _MemberDriveUiStatus.driveUnknown;
  }

  final inDrive = email.isNotEmpty && driveWriterEmails.contains(email);
  final confirmed = _dynBool(member['driveAccessConfirmed']);

  if (inDrive) return _MemberDriveUiStatus.accepted;
  if (confirmed && !inDrive) return _MemberDriveUiStatus.rejected;
  if (grant == false) return _MemberDriveUiStatus.appOnly;
  return _MemberDriveUiStatus.pending;
}

class _StatusStyle {
  const _StatusStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

_StatusStyle _styleFor(_MemberDriveUiStatus s, ThemeData theme) {
  switch (s) {
    case _MemberDriveUiStatus.owner:
      return _StatusStyle(
        'Owner',
        theme.colorScheme.primary,
        Icons.star_rounded,
      );
    case _MemberDriveUiStatus.accepted:
      return _StatusStyle(
        'Accepted — has Drive access',
        Colors.green.shade700,
        Icons.check_circle_outline,
      );
    case _MemberDriveUiStatus.pending:
      return _StatusStyle(
        'Pending — invite not visible in Drive yet',
        Colors.orange.shade800,
        Icons.schedule,
      );
    case _MemberDriveUiStatus.rejected:
      return _StatusStyle(
        'Declined or removed — no Drive access',
        Colors.red.shade700,
        Icons.cancel_outlined,
      );
    case _MemberDriveUiStatus.appOnly:
      return _StatusStyle(
        'App only — Drive invite failed or not sent',
        Colors.blueGrey.shade700,
        Icons.cloud_off_outlined,
      );
    case _MemberDriveUiStatus.driveUnknown:
      return _StatusStyle(
        'Drive status unknown — tap refresh',
        Colors.deepPurple.shade700,
        Icons.help_outline,
      );
  }
}

/// Share sheet: shows name, members with Drive sync status, new email field.
class ShareSpreadsheetDialog extends StatefulWidget {
  const ShareSpreadsheetDialog({
    super.key,
    required this.spreadsheetId,
    required this.fallbackSheetName,
    required this.ownerEmail,
    required this.firebaseDatabaseService,
    required this.driveShareService,
  });

  final String spreadsheetId;
  final String fallbackSheetName;
  final String ownerEmail;
  final FirebaseDatabaseService firebaseDatabaseService;
  final GoogleDriveShareService driveShareService;

  static Future<void> show(
    BuildContext context, {
    required String spreadsheetId,
    required String fallbackSheetName,
    required String ownerEmail,
    required FirebaseDatabaseService firebaseDatabaseService,
    required GoogleDriveShareService driveShareService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ShareSpreadsheetDialog(
        spreadsheetId: spreadsheetId,
        fallbackSheetName: fallbackSheetName,
        ownerEmail: ownerEmail,
        firebaseDatabaseService: firebaseDatabaseService,
        driveShareService: driveShareService,
      ),
    );
  }

  @override
  State<ShareSpreadsheetDialog> createState() => _ShareSpreadsheetDialogState();
}

class _ShareSpreadsheetDialogState extends State<ShareSpreadsheetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _loading = true;
  bool _sharing = false;
  String? _retryEmail;
  bool _personalSheetNoShare = false;

  String _sheetTitle = '';
  List<Map<String, dynamic>> _members = [];
  Set<String> _driveWriterEmails = {};
  String? _driveListError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _driveListError = null;
      _personalSheetNoShare = false;
    });

    if (await widget.firebaseDatabaseService
        .isSpreadsheetPersonal(widget.spreadsheetId)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _personalSheetNoShare = true;
      });
      return;
    }

    final meta = await widget.firebaseDatabaseService
        .getSpreadsheetMeta(widget.spreadsheetId);
    final nameFromMeta = meta['name']?.trim();
    final members = await widget.firebaseDatabaseService
        .getSpreadsheetMembers(widget.spreadsheetId);

    final driveResult =
        await widget.driveShareService.listWriterEmails(widget.spreadsheetId);
    final driveEmails = driveResult.isSuccess
        ? driveResult.emails
        : <String>{};
    if (!driveResult.isSuccess) {
      _driveListError = driveResult.errorMessage;
    }

    for (final m in members) {
      final role = m['role']?.toString() ?? '';
      if (role == 'owner') continue;
      final email = m['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) continue;
      if (driveEmails.contains(email) && !_dynBool(m['driveAccessConfirmed'])) {
        await widget.firebaseDatabaseService.updateSpreadsheetMemberDriveFields(
          widget.spreadsheetId,
          email,
          driveAccessConfirmed: true,
        );
      }
    }

    final membersAfter = driveResult.isSuccess
        ? await widget.firebaseDatabaseService
            .getSpreadsheetMembers(widget.spreadsheetId)
        : members;

    if (!mounted) return;
    setState(() {
      _sheetTitle = (nameFromMeta != null && nameFromMeta.isNotEmpty)
          ? nameFromMeta
          : widget.fallbackSheetName;
      _members = membersAfter;
      _driveWriterEmails = driveEmails;
      _loading = false;
    });
  }

  void _showSnack(String text, {Color? bg, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg,
        duration: const Duration(seconds: 6),
        action: action,
      ),
    );
  }

  Future<void> _shareWithEmail(String email) async {
    final sheetName = _sheetTitle.isNotEmpty
        ? _sheetTitle
        : widget.fallbackSheetName;
    final success = await widget.firebaseDatabaseService.shareSpreadsheet(
      ownerEmail: widget.ownerEmail,
      inviteeEmail: email,
      spreadsheetId: widget.spreadsheetId,
      spreadsheetName: sheetName,
    );

    if (!success) {
      _showSnack(
        'Failed to share spreadsheet in the app.',
        bg: Colors.red,
      );
      return;
    }

    final driveResult = await widget.driveShareService.grantEditorAccess(
      widget.spreadsheetId,
      email,
    );

    await widget.firebaseDatabaseService.updateSpreadsheetMemberDriveFields(
      widget.spreadsheetId,
      email,
      driveLastGrantSuccess: driveResult.success,
    );

    final driveOk = driveResult.success;
    if (driveOk) {
      _showSnack(
        'Shared with $email (app + Google Drive editor).',
        bg: Colors.green.shade700,
      );
    } else {
      _showSnack(
        driveResult.userMessage ??
            'Drive invite failed — share from Google Sheets if needed.',
        bg: Colors.orange.shade800,
        action: driveResult.suggestEnableDriveApi
            ? SnackBarAction(
                label: 'Enable Drive API',
                textColor: Colors.white,
                onPressed: () async {
                  final uri = Uri.parse(kGoogleDriveApiLibraryUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              )
            : null,
      );
    }

    _emailController.clear();
    await _load();
  }

  Future<void> _requestDriveAgain(String email) async {
    setState(() {
      _retryEmail = email;
    });
    final driveResult = await widget.driveShareService.grantEditorAccess(
      widget.spreadsheetId,
      email,
    );
    await widget.firebaseDatabaseService.updateSpreadsheetMemberDriveFields(
      widget.spreadsheetId,
      email,
      driveLastGrantSuccess: driveResult.success,
    );
    if (!mounted) return;
    setState(() => _retryEmail = null);

    if (driveResult.success) {
      _showSnack(
        'Drive invite sent again to $email.',
        bg: Colors.green.shade700,
      );
    } else {
      _showSnack(
        driveResult.userMessage ?? 'Drive request failed.',
        bg: Colors.orange.shade800,
        action: driveResult.suggestEnableDriveApi
            ? SnackBarAction(
                label: 'Enable Drive API',
                textColor: Colors.white,
                onPressed: () async {
                  final uri = Uri.parse(kGoogleDriveApiLibraryUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              )
            : null,
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Share spreadsheet',
              style: theme.textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _personalSheetNoShare
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Personal sheets cannot be shared from the app. '
                      'Open sharing for your home (common) sheet instead.',
                    ),
                  )
                : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _sheetTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${widget.spreadsheetId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_driveListError != null) ...[
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber.shade900,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Could not load Google Drive permissions. '
                                    'Statuses may show as pending. $_driveListError',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Members',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_members.isEmpty)
                        Text(
                          'No members yet. Add an email below.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ..._sortedMembers().map((m) => _memberTile(m, theme)),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Share with someone new',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_sharing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter an email';
                          }
                          if (!value.trim().contains('@')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading || _sharing ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _loading || _sharing
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() => _sharing = true);
                  try {
                    await _shareWithEmail(_emailController.text.trim());
                  } finally {
                    if (mounted) setState(() => _sharing = false);
                  }
                },
          child: _sharing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Share'),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _sortedMembers() {
    final copy = List<Map<String, dynamic>>.from(_members);
    copy.sort((a, b) {
      final ra = a['role']?.toString() ?? '';
      final rb = b['role']?.toString() ?? '';
      if (ra == 'owner' && rb != 'owner') return -1;
      if (rb == 'owner' && ra != 'owner') return 1;
      final ea = a['email']?.toString().toLowerCase() ?? '';
      final eb = b['email']?.toString().toLowerCase() ?? '';
      return ea.compareTo(eb);
    });
    return copy;
  }

  Widget _memberTile(Map<String, dynamic> member, ThemeData theme) {
    final email = member['email']?.toString() ?? '';
    final status = _statusForMember(
      member,
      _driveWriterEmails,
      _driveListError == null,
    );
    final st = _styleFor(status, theme);
    final showRetry = status == _MemberDriveUiStatus.rejected;
    final retrying = _retryEmail == email.trim().toLowerCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(st.icon, color: st.color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    st.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: st.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (showRetry)
              TextButton(
                onPressed: retrying || _sharing
                    ? null
                    : () => _requestDriveAgain(email),
                child: retrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Request again'),
              ),
          ],
        ),
      ),
    );
  }
}
