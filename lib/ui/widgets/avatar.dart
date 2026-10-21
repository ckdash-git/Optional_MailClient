import 'package:flutter/material.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';

/// Circle with up to two initials. Neutral grey like iOS Contacts; with [coded] it takes an
/// iOS system colour that is stable per [seed] (accounts and calendars).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    super.key,
    this.seed,
    this.radius = 20,
    this.coded = false,
    this.colorIndex,
  });

  final String name;
  final String? seed;
  final double radius;
  final bool coded;

  /// Position of the account in the account list; takes precedence over the seed's hash.
  final int? colorIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = Palette.of(theme.brightness);
    final bg = !coded
        ? t.grouped
        : colorIndex != null
        ? systemColorAt(colorIndex!, theme.brightness)
        : systemColor(seed ?? name, theme.brightness);
    final fg = coded ? Colors.white : t.mute;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        foregroundColor: fg,
        child: Text(
          initialsOf(name),
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
