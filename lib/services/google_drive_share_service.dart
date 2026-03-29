import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/io_client.dart' as io;

import 'firebase_auth_service.dart';
import 'google_sheets_service.dart';

/// Result of [GoogleDriveShareService.grantEditorAccess].
class GoogleDriveGrantResult {
  final bool success;
  /// When [success] is false, a short explanation for the user.
  final String? userMessage;
  /// When true, show an action to open Google Cloud Console (Drive API library).
  final bool suggestEnableDriveApi;

  const GoogleDriveGrantResult._({
    required this.success,
    this.userMessage,
    this.suggestEnableDriveApi = false,
  });

  factory GoogleDriveGrantResult.ok() =>
      const GoogleDriveGrantResult._(success: true);

  factory GoogleDriveGrantResult.fail({
    required String userMessage,
    bool suggestEnableDriveApi = false,
  }) =>
      GoogleDriveGrantResult._(
        success: false,
        userMessage: userMessage,
        suggestEnableDriveApi: suggestEnableDriveApi,
      );
}

/// Open this in a browser to enable Drive API for the Google Cloud project
/// linked to Firebase (pick your project in the top bar if needed).
const String kGoogleDriveApiLibraryUrl =
    'https://console.cloud.google.com/apis/library/drive.googleapis.com';

/// Lowercased emails that have writer-level (or higher) access on the file, from Drive API.
class DriveWriterEmailsResult {
  final Set<String> emails;
  final String? errorMessage;

  const DriveWriterEmailsResult._(this.emails, this.errorMessage);

  factory DriveWriterEmailsResult.success(Set<String> emails) =>
      DriveWriterEmailsResult._(emails, null);

  factory DriveWriterEmailsResult.failure(String message) =>
      DriveWriterEmailsResult._({}, message);

  bool get isSuccess => errorMessage == null;
}

bool _driveRoleIsWriterOrHigher(String? role) {
  if (role == null) return false;
  const ok = {
    'owner',
    'organizer',
    'fileOrganizer',
    'writer',
  };
  return ok.contains(role);
}

/// Grants Google Drive editor (writer) permission on a file so the invitee can use the Sheets API.
/// Requires Google Sign-In scope `https://www.googleapis.com/auth/drive` (see [FirebaseAuthService]).
/// Narrower `drive.file` is not enough for arbitrary spreadsheet IDs — Drive returns 404.
///
/// **403 "API has not been used or is disabled"**: In [Google Cloud Console](https://console.cloud.google.com),
/// enable **Google Drive API** for the same project as your Firebase app, wait a few minutes, then try again.
class GoogleDriveShareService {
  final FirebaseAuthService _auth = FirebaseAuthService();

  /// Lists `user`/`group` permissions with writer-or-higher roles (emails lowercased).
  Future<DriveWriterEmailsResult> listWriterEmails(String fileId) async {
    try {
      final token = await _auth.getAccessToken();
      if (token == null || token.isEmpty) {
        return DriveWriterEmailsResult.failure(
          'Could not get Google sign-in token.',
        );
      }

      final httpClient = AuthenticatedClient(io.IOClient(), token);
      final api = drive.DriveApi(httpClient);

      final emails = <String>{};
      String? pageToken;
      do {
        final list = await api.permissions.list(
          fileId,
          pageSize: 100,
          pageToken: pageToken,
          supportsAllDrives: true,
          $fields: 'nextPageToken, permissions(emailAddress,id,role,type)',
        );
        final items = list.permissions;
        if (items != null) {
          for (final p in items) {
            final t = p.type?.toLowerCase();
            if (t != 'user' && t != 'group') continue;
            final addr = p.emailAddress?.trim().toLowerCase();
            if (addr == null || addr.isEmpty) continue;
            if (_driveRoleIsWriterOrHigher(p.role)) {
              emails.add(addr);
            }
          }
        }
        pageToken = list.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      return DriveWriterEmailsResult.success(emails);
    } catch (e, st) {
      debugPrint('GoogleDriveShareService: listWriterEmails failed: $e');
      debugPrint('$st');
      return DriveWriterEmailsResult.failure(
        _messageForError(e),
      );
    }
  }

  Future<GoogleDriveGrantResult> grantEditorAccess(String fileId, String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return GoogleDriveGrantResult.fail(userMessage: 'Invalid email.');
    }

    try {
      final token = await _auth.getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('GoogleDriveShareService: no access token');
        return GoogleDriveGrantResult.fail(
          userMessage:
              'Could not get Google sign-in token. Sign out and sign in again.',
        );
      }

      final httpClient = AuthenticatedClient(io.IOClient(), token);
      final api = drive.DriveApi(httpClient);

      final permission = drive.Permission()
        ..type = 'user'
        ..role = 'writer'
        ..emailAddress = trimmed;

      await api.permissions.create(
        permission,
        fileId,
        sendNotificationEmail: true,
        supportsAllDrives: true,
      );
      debugPrint('GoogleDriveShareService: writer permission for $trimmed');
      return GoogleDriveGrantResult.ok();
    } catch (e, st) {
      debugPrint('GoogleDriveShareService: grantEditorAccess failed: $e');
      debugPrint('$st');
      return GoogleDriveGrantResult.fail(
        userMessage: _messageForError(e),
        suggestEnableDriveApi: _isDriveApiDisabledError(e),
      );
    }
  }

  bool _isDriveApiDisabledError(Object e) {
    final s = e.toString();
    return s.contains('403') &&
        (s.contains('Drive API has not been used') ||
            s.contains('has not been used in project') ||
            s.contains('it is disabled'));
  }

  bool _isDriveFileNotFoundError(Object e) {
    final s = e.toString();
    return s.contains('404') ||
        s.contains('File not found') ||
        s.toLowerCase().contains('not found:');
  }

  String _messageForError(Object e) {
    final s = e.toString();
    if (_isDriveFileNotFoundError(e)) {
      return 'Google Drive could not open this spreadsheet (404). '
          'Check the ID, confirm the file is in your Google account, and that you are the owner. '
          'If you just updated app permissions, sign out and sign in again. '
          'You can still share from Google Sheets in a browser.';
    }
    if (_isDriveApiDisabledError(e)) {
      return 'Google Drive API is off for this app’s Cloud project. Enable '
          '"Google Drive API" in Google Cloud Console, wait a few minutes, then share again. '
          'Sharing in the app (Firebase) still worked — only the automatic Drive invite failed.';
    }
    if (s.contains('403')) {
      return 'Google denied Drive sharing (403). You may lack permission to '
          'share this file, or the project needs Drive API enabled.';
    }
    if (s.contains('401') || s.toLowerCase().contains('unauthorized')) {
      return 'Google auth failed for Drive. Sign out, sign in again, then retry.';
    }
    return 'Could not add Drive editor access. You can still share the sheet '
        'manually from Google Sheets.';
  }
}
