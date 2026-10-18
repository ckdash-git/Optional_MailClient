#!/usr/bin/env bash
# Fails if any module linked into the master binary is not under a permissive licence,
# and writes THIRD_PARTY_NOTICES.txt for distribution. Run from server/.
set -euo pipefail
out=${1:-THIRD_PARTY_NOTICES.txt}
: > "$out"
fail=0
while read -r mod dir; do
  [ "$mod" = "github.com/ckdash-git/optional_mailclient/server" ] && continue
  lic=$(find "$dir" -maxdepth 1 -iname 'LICEN[CS]E*' -o -maxdepth 1 -iname 'COPYING*' | head -1)
  if [ -z "$lic" ]; then echo "NO LICENSE FILE: $mod"; fail=1; continue; fi
  text=$(tr -s '[:space:]' ' ' < "$lic")
  if grep -qiE 'GNU (GENERAL|AFFERO|LESSER) PUBLIC|Mozilla Public License|Server Side Public License|Business Source License|Commons Clause' <<<"$text"; then
    echo "COPYLEFT/NON-PERMISSIVE: $mod ($lic)"; fail=1; continue
  fi
  if ! grep -qiE 'Permission is hereby granted|Redistribution and use in source and binary forms|Apache License|Permission to use, copy, modify|public domain' <<<"$text"; then
    echo "UNRECOGNISED LICENSE: $mod ($lic)"; fail=1; continue
  fi
  { echo "==== $mod"; cat "$lic"; echo; } >> "$out"
done < <(go list -deps -f '{{with .Module}}{{.Path}} {{.Dir}}{{end}}' ./cmd/master | sort -u)
[ "$fail" = 0 ] && echo "LICENSES_OK ($(grep -c '^==== ' "$out") modules)"
exit "$fail"
