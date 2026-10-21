import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/push.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/widgets/temp_files.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = Session(SecureKeyValueStore());
  final api = ApiClient(session);

  // Push is optional: without Firebase config files this returns null and
  // the app relies on the WebSocket alone.
  final push = await PushService.initialize().timeout(
    const Duration(seconds: 10),
    onTimeout: () => null,
  );

  session.wipeHooks.add(wipeTempFiles);
  if (push != null) session.wipeHooks.add(push.unregister);
  await session.load();

  runApp(MailApp(api: api, push: push));
}
