import 'dart:typed_data';

/// Web has no file system; downloads go through the browser instead.
Future<String> writeTempFile(String name, Uint8List bytes) =>
    Future.error(UnsupportedError('No file system on this platform'));

Future<void> wipeTempFiles() async {}
