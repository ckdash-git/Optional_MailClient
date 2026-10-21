import 'package:optional_mail_client/api/cache.dart';

/// Web has no private file system, so nothing is kept after the tab closes.
Future<BlobStore> openBlobStore() async => MemoryBlobStore();
