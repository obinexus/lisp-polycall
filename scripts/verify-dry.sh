#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/lisp_polycall.c" "$root/src/lisp-polycall.lisp"; then
    echo "lisp-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/lisp_polycall.c"
grep -F -q 'cffi:defcfun' "$root/src/lisp-polycall.lisp"
grep -F -q '(config-path :string)' "$root/src/lisp-polycall.lisp"
grep -F -q 'cffi:*default-foreign-encoding* :utf-8' \
    "$root/src/lisp-polycall.lisp"

echo "lisp-polycall thin-adapter check: PASS"
