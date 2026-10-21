/// Temporary files for downloaded attachments. Wiped on sign out.
library;

export 'package:optional_mail_client/ui/widgets/temp_files_stub.dart'
    if (dart.library.io) 'package:optional_mail_client/ui/widgets/temp_files_io.dart';
