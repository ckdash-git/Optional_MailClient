import 'package:flutter/material.dart';
import 'package:optional_mail_client/ui/format.dart';

/// Circle with up to two initials; the colour is stable per [seed].
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    super.key,
    this.seed,
    this.radius = 20,
  });

  final String name;
  final String? seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    ];
    final key = (seed ?? name).toLowerCase();
    var hash = 0;
    for (final c in key.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final (bg, fg) = palette[hash % palette.length];
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
