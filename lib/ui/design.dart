import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Timetable palette: charcoal ink, white ground, one signal red. Dark mode uses
/// the iOS elevated-black ground and the iOS system red.
class Palette {
  const Palette._(
    this.ink,
    this.mute,
    this.ground,
    this.grouped,
    this.line,
    this.red,
    this.onRed,
  );

  final Color ink;
  final Color mute;
  final Color ground;
  final Color grouped;
  final Color line;
  final Color red;

  /// Text on a red fill: white on the light red, black on the lighter dark-mode red (white is 3.4:1 there).
  final Color onRed;

  static const light = Palette._(
    Color(0xFF1D1D1F),
    Color(0xFF6E6E73),
    Color(0xFFFFFFFF),
    Color(0xFFF2F2F7),
    Color(0xFFD1D1D6),
    Color(0xFFD6001C),
    Color(0xFFFFFFFF),
  );
  static const dark = Palette._(
    Color(0xFFF5F5F7),
    Color(0xFF98989D),
    Color(0xFF000000),
    Color(0xFF1C1C1E),
    Color(0xFF38383A),
    Color(0xFFFF453A),
    Color(0xFF000000),
  );

  static Palette of(Brightness b) => b == Brightness.dark ? dark : light;
}

/// iOS system colours (light, dark). They colour-code accounts and calendars so
/// two of them are never told apart by red alone.
const _system = <(Color, Color)>[
  (Color(0xFF007AFF), Color(0xFF0A84FF)), // blue
  (Color(0xFF34C759), Color(0xFF30D158)), // green
  (Color(0xFFFF9500), Color(0xFFFF9F0A)), // orange
  (Color(0xFFAF52DE), Color(0xFFBF5AF2)), // purple
  (Color(0xFF00A5A8), Color(0xFF40C8E0)), // teal
  (Color(0xFFFF2D55), Color(0xFFFF375F)), // pink
];

Color systemColor(String seed, Brightness b) {
  var hash = 0;
  for (final c in seed.toLowerCase().codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  final (light, dark) = _system[hash % _system.length];
  return b == Brightness.dark ? dark : light;
}

/// `?platform=ios` / `?platform=android` previews the other design on the web build.
TargetPlatform? previewPlatform() {
  if (!kIsWeb) return null;
  return switch (Uri.base.queryParameters['platform']) {
    'ios' => TargetPlatform.iOS,
    'android' => TargetPlatform.android,
    _ => null,
  };
}

bool isIOS(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

ThemeData buildTheme(Brightness brightness, {TargetPlatform? platform}) {
  final t = Palette.of(brightness);
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  final scheme = ColorScheme.fromSeed(seedColor: t.red, brightness: brightness)
      .copyWith(
        primary: t.red,
        onPrimary: t.onRed,
        primaryContainer: t.grouped,
        onPrimaryContainer: t.ink,
        secondaryContainer: t.grouped,
        onSecondaryContainer: t.ink,
        surface: t.ground,
        onSurface: t.ink,
        onSurfaceVariant: t.mute,
        surfaceContainerLowest: t.ground,
        surfaceContainerLow: t.ground,
        surfaceContainer: t.grouped,
        surfaceContainerHigh: t.grouped,
        surfaceContainerHighest: t.grouped,
        outline: t.mute,
        outlineVariant: t.line,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    colorScheme: scheme,
    platform: platform,
    useMaterial3: true,
  );
  final radius = BorderRadius.circular(12);
  return base.copyWith(
    scaffoldBackgroundColor: t.ground,
    textTheme: base.textTheme.copyWith(
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.ground,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: ios,
      titleTextStyle: TextStyle(
        color: t.ink,
        fontSize: ios ? 17 : 22,
        fontWeight: ios ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 0.5, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: t.grouped,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? t.red : t.mute,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? t.red : t.mute,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.ground,
      indicatorColor: t.grouped,
      selectedIconTheme: IconThemeData(color: t.red),
      selectedLabelTextStyle: TextStyle(
        color: t.red,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.red,
        foregroundColor: t.onRed,
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(
          borderRadius: ios ? radius : BorderRadius.circular(24),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(44, 48),
        side: BorderSide(color: t.ink, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: ios ? radius : BorderRadius.circular(24),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.red,
      foregroundColor: t.onRed,
      elevation: 3,
      shape: ios
          ? const StadiumBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: t.grouped,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.ink, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? const Color(0xFF34C759) : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.grouped,
      selectedColor: t.ink,
      labelStyle: TextStyle(color: t.ink),
      secondaryLabelStyle: TextStyle(color: t.ground),
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.ground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ios ? 14 : 28),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      contentTextStyle: TextStyle(color: t.ground),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 8),
  );
}

typedef TabItem = ({IconData icon, IconData selected, String label});

/// iOS liquid-glass tab bar: a floating, blurred, translucent capsule over the content,
/// with a lighter glass capsule behind the selected item. Content scrolls under it.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    required this.items,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  static const height = 64.0;

  final List<TabItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final t = Palette.of(b);
    final dark = b == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduceTransparency = MediaQuery.maybeHighContrastOf(context) ?? false;
    final fill = dark ? const Color(0xFF2C2C2E) : Colors.white;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom > 0 ? bottom - 8 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill.withValues(
                  alpha: reduceTransparency ? 0.98 : (dark ? 0.55 : 0.62),
                ),
                borderRadius: BorderRadius.circular(height / 2),
                // Specular rim: bright at the top edge, fading toward the bottom.
                border: Border.all(
                  color: (dark ? Colors.white : Colors.white).withValues(
                    alpha: dark ? 0.18 : 0.85,
                  ),
                  width: 0.8,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.10 : 0.35),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
              child: SizedBox(
                height: height,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _GlassItem(
                          item: items[i],
                          selected: i == selected,
                          tint: t.red,
                          idle: t.ink.withValues(alpha: 0.62),
                          glass: dark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.07),
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassItem extends StatelessWidget {
  const _GlassItem({
    required this.item,
    required this.selected,
    required this.tint,
    required this.idle,
    required this.glass,
    required this.onTap,
  });

  final TabItem item;
  final bool selected;
  final Color tint;
  final Color idle;
  final Color glass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? tint : idle;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? glass : Colors.transparent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? item.selected : item.icon,
                    size: 24,
                    color: color,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
