#!/usr/bin/env bash
# Fails if any package in pubspec.lock (direct or transitive) is not permissively
# licensed. Run from the repository root after `flutter pub get`.
set -euo pipefail
cache=${PUB_CACHE:-$HOME/.pub-cache}
fail=0; n=0
while read -r name version; do
  dir="$cache/hosted/pub.dev/$name-$version"
  [ -d "$dir" ] || { echo "NOT IN CACHE: $name $version"; fail=1; continue; }
  lic=$(find "$dir" -maxdepth 1 \( -iname 'LICEN[CS]E*' -o -iname 'COPYING*' \) | head -1)
  [ -n "$lic" ] || { echo "NO LICENSE FILE: $name"; fail=1; continue; }
  text=$(tr -s '[:space:]' ' ' < "$lic")
  if grep -qiE 'GNU (GENERAL|AFFERO|LESSER) PUBLIC|Mozilla Public License|Server Side Public License|Business Source License|Commons Clause|Syncfusion' <<<"$text"; then
    echo "COPYLEFT/NON-PERMISSIVE: $name ($lic)"; fail=1; continue
  fi
  if ! grep -qiE 'Permission is hereby granted|Redistribution and use in source and binary forms|Apache License|Permission to use, copy, modify' <<<"$text"; then
    echo "UNRECOGNISED LICENSE: $name ($lic)"; fail=1; continue
  fi
  n=$((n+1))
done < <(awk '/^  [a-z0-9_]+:$/{name=$1; sub(":","",name)} /source: hosted/{h=1} /^    version:/{ if (h) {gsub("\"","",$2); print name, $2}; h=0 }' pubspec.lock)
[ "$fail" = 0 ] && echo "APP_LICENSES_OK ($n hosted packages)"
exit "$fail"
