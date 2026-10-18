import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Directory> _root() async =>
    Directory('${(await getTemporaryDirectory()).path}/attachments');

/// Writes [bytes] to a fresh temporary directory and returns the file path.
Future<String> writeTempFile(String name, Uint8List bytes) async {
  final root = await _root();
  final dir = Directory(
    '${root.path}/${DateTime.now().microsecondsSinceEpoch}',
  );
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Deletes downloaded attachments, including copies made for sharing.
Future<void> wipeTempFiles() async {
  final tmp = await getTemporaryDirectory();
  for (final dir in [
    Directory('${tmp.path}/attachments'),
    Directory('${tmp.path}/share_plus'),
  ]) {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Missing already.
    }
  }
}
