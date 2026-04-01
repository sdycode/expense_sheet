import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/io_client.dart' as io;

import 'firebase_auth_service.dart';
import 'google_sheets_service.dart';

/// A Google Spreadsheet as returned from Drive [files.list].
class DriveSpreadsheetRef {
  DriveSpreadsheetRef({
    required this.id,
    required this.name,
    this.modifiedTime,
    required this.ownedByMe,
    this.compatible,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final bool ownedByMe;

  /// Whether row 1 of Sheet1 matches the 10-column expense layout.
  /// Null means not yet checked.
  final bool? compatible;

  DriveSpreadsheetRef copyWith({bool? compatible}) => DriveSpreadsheetRef(
        id: id,
        name: name,
        modifiedTime: modifiedTime,
        ownedByMe: ownedByMe,
        compatible: compatible ?? this.compatible,
      );
}

/// Lists spreadsheet files from Google Drive (not Firebase).
class GoogleDriveSpreadsheetListService {
  final FirebaseAuthService _auth = FirebaseAuthService();

  static const String _spreadsheetMime =
      'application/vnd.google-apps.spreadsheet';

  /// Lists all spreadsheets the user can see (owned + shared).
  /// Set [ownedByMeOnly] to restrict to files where `'me' in owners` in the query.
  Future<List<DriveSpreadsheetRef>> listSpreadsheets({
    bool ownedByMeOnly = false,
  }) async {
    final token = await _auth.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not get Google sign-in token.');
    }

    final httpClient = AuthenticatedClient(io.IOClient(), token);
    final api = drive.DriveApi(httpClient);

    final q = StringBuffer("mimeType='$_spreadsheetMime' and trashed=false");
    if (ownedByMeOnly) {
      q.write(" and 'me' in owners");
    }

    final out = <DriveSpreadsheetRef>[];
    String? pageToken;
    final userEmail = _auth.userEmail?.trim().toLowerCase();

    do {
      final list = await api.files.list(
        q: q.toString(),
        pageSize: 100,
        pageToken: pageToken,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields:
            'nextPageToken, files(id, name, modifiedTime, owners(emailAddress))',
      );

      final files = list.files;
      if (files != null) {
        for (final f in files) {
          final id = f.id;
          if (id == null || id.isEmpty) continue;
          final rawName = f.name?.trim() ?? '';
          final name =
              rawName.isEmpty ? 'Untitled spreadsheet' : rawName;
          final ownedByMe = _fileOwnedByMe(f, userEmail);
          if (ownedByMeOnly && !ownedByMe) continue;
          out.add(
            DriveSpreadsheetRef(
              id: id,
              name: name,
              modifiedTime: f.modifiedTime,
              ownedByMe: ownedByMe,
            ),
          );
        }
      }
      pageToken = list.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    return out;
  }

  bool _fileOwnedByMe(drive.File f, String? userEmail) {
    final owners = f.owners;
    if (owners == null || owners.isEmpty) return false;
    if (userEmail == null || userEmail.isEmpty) return false;
    for (final o in owners) {
      final e = o.emailAddress?.trim().toLowerCase();
      if (e != null && e == userEmail) return true;
    }
    return false;
  }
}
