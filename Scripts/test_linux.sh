#!/usr/bin/env bash
# GRDB 7.0.0 expects SQLite snapshot symbols that Ubuntu's SQLite omits.
# Build an isolated development library; iOS/macOS use Apple's system SQLite.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/folio-sqlite"
SWIFT_BIN="${FOLIO_SWIFT:-swift}"
mkdir -p "$TASK_CACHE"
if [[ ! -f "$TASK_CACHE/libsqlite3.so" ]]; then
  curl -fsSL --retry 2 https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip -o "$TASK_CACHE/source.zip"
  python3 - "$TASK_CACHE" <<'PY'
import sys, zipfile
from pathlib import Path
target = Path(sys.argv[1]).resolve()
with zipfile.ZipFile(target / "source.zip") as source:
    for member in source.namelist():
        if not (target / member).resolve().is_relative_to(target):
            raise RuntimeError("Invalid archive path")
    source.extractall(target)
PY
  cc -shared -fPIC -O2 -DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_COLUMN_METADATA "$TASK_CACHE/sqlite-amalgamation-3450100/sqlite3.c" \
    -o "$TASK_CACHE/libsqlite3.so" -lm -ldl -lpthread
fi
cd "$TASK_ROOT"
LD_LIBRARY_PATH="$TASK_CACHE${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$SWIFT_BIN" test -Xlinker "-L$TASK_CACHE" "$@"
