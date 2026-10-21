import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:optional_mail_client/ui/widgets/temp_files.dart';
import 'package:share_plus/share_plus.dart';

/// Makes a server-provided file name safe to use on the local file system.
String safeFileName(String name) {
  var s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();
  if (s.isEmpty) s = 'attachment';
  if (s.length > 120) {
    final dot = s.lastIndexOf('.');
    final ext = dot > 0 && s.length - dot <= 10 ? s.substring(dot) : '';
    s = s.substring(0, 120 - ext.length) + ext;
  }
  return s;
}

/// Hands a downloaded attachment to the user.
///
/// Mobile: opens the system share sheet (open with, save to Files, ...).
/// Desktop: asks where to save it. Web: browser download.
/// Returns a short confirmation, or null if the user cancelled.
Future<String?> saveAttachment({
  required Uint8List bytes,
  required String filename,
  required String contentType,
  Rect? origin,
}) async {
  final name = safeFileName(filename);
  final mime = contentType.split(';').first.trim();
  if (kIsWeb) {
    await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(name);
    return 'Downloaded $name';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      final path = await writeTempFile(name, bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: mime, name: name)],
          sharePositionOrigin: origin,
        ),
      );
      return null;
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      final location = await getSaveLocation(suggestedName: name);
      if (location == null) return null;
      await XFile.fromData(
        bytes,
        name: name,
        mimeType: mime,
      ).saveTo(location.path);
      return 'Saved $name';
  }
}
