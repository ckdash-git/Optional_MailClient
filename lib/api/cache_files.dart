import 'dart:convert';
import 'dart:io';

import 'package:optional_mail_client/api/cache.dart';
import 'package:path_provider/path_provider.dart';

/// One file per key inside [root], which must be app-private storage. File
/// names are the hex of the key, so no key can escape the directory.
class FileBlobStore implements BlobStore {
  FileBlobStore(this.root);

  final Directory root;

  static String _name(String key) =>
      utf8.encode(key).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String? _key(String name) {
    if (name.length.isOdd) return null;
    try {
      return utf8.decode([
        for (var i = 0; i < name.length; i += 2)
          int.parse(name.substring(i, i + 2), radix: 16),
      ]);
    } on FormatException {
      return null;
    }
  }

  File _file(String key) => File('${root.path}/${_name(key)}');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    try {
      return await f.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    await root.create(recursive: true);
    final f = _file(key);
    // Write beside, then rename, so a crash never leaves half a file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _file(key).delete();
    } on FileSystemException {
      // already gone
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    if (!root.existsSync()) return const [];
    final out = <String>[];
    await for (final e in root.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name.endsWith('.tmp')) continue;
      final key = _key(name);
      if (key != null && key.startsWith(prefix)) out.add(key);
    }
    return out;
  }

  @override
  Future<void> clear() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// The on-device cache directory: the app's private support folder, which the
/// OS sandboxes from other apps.
Future<BlobStore> openBlobStore() async {
  final dir = await getApplicationSupportDirectory();
  return FileBlobStore(Directory('${dir.path}/mail_cache'));
}
