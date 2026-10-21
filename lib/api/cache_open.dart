/// Opens the on-device store: files where there is a file system, memory on web.
library;

export 'package:optional_mail_client/api/cache_open_stub.dart'
    if (dart.library.io) 'package:optional_mail_client/api/cache_files.dart';
