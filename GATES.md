# Gates: Timetable UI redesign (adaptive: iOS liquid glass, Android Material)

Direction chosen by the owner: Timetable (charcoal, white, signal red; strict hairlines,
tabular figures), with iOS-style colour coding and widgets, a liquid-glass floating tab
bar on iOS, and Material 3 on Android. Commands run from the repository root in bash.

- [x] G1 The app analyses clean under the strict options.
  CHECK: /opt/sdk/flutter/bin/flutter analyze --suppress-analytics 2>&1 | tail -1
  EXPECT: No issues found!
- [x] G2 All widget and unit tests pass, including the new design tests.
  CHECK: /opt/sdk/flutter/bin/flutter test --suppress-analytics 2>&1 | tail -1
  EXPECT: All tests passed!
- [x] G3 The design tests pin the platform split: glass tab bar on iOS, NavigationBar on Android.
  CHECK: /opt/sdk/flutter/bin/flutter test test/design_test.dart --suppress-analytics 2>&1 | tail -1
  EXPECT: All tests passed!
- [x] G4 Text and signal red meet WCAG contrast in light and dark (4.5:1 body).
  CHECK: /opt/sdk/flutter/bin/flutter test test/design_test.dart --plain-name contrast --suppress-analytics 2>&1 | tail -1
  EXPECT: All tests passed!
- [x] G5 Licences are still all permissive.
  CHECK: ./scripts/check-app-licenses.sh
  EXPECT: APP_LICENSES_OK
- [x] G6 The web build compiles in release mode.
  CHECK: /opt/sdk/flutter/bin/flutter build web --release --no-web-resources-cdn --suppress-analytics 2>&1 | tail -3
  EXPECT: Built build/web
- [x] G7 DESIGN.md exists and records the tokens.
  CHECK: grep -q 'signal red' DESIGN.md && echo GATE_DESIGN_OK
  EXPECT: GATE_DESIGN_OK

## Manual (cannot be run here)

- [ ] M1 Real iOS Simulator screenshots (needs macOS and Xcode; not available on this Linux host).
- [ ] M2 Real Android emulator screenshots (no Android SDK on this host).
- [ ] M3 Owner approves the rendered iOS and Android screenshots.

## Last run

All 7 runnable gates met (G1-G7). M1-M3 stay open: no iOS Simulator or Android emulator on this Linux host, and the owner has not yet approved the screenshots.
