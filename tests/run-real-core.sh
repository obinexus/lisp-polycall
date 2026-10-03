#!/bin/sh
# lisp-polycall: load the ASDF system (CFFI straight onto libpolycall, no C
# shim) in SBCL and run tests/real-core.lisp against the REAL installed core.
#
#   sh tests/run-real-core.sh
#
# The system is found the way an installed one is: through
# CL_SOURCE_REGISTRY (this checkout, or the directory in
# LISP_POLYCALL_SOURCE_DIR, e.g. an unpacked package), not by loading the
# .asd file by path.
#
# Needs sbcl with ASDF and CFFI (Debian: sbcl cl-cffi; or Quicklisp), a C
# compiler (loader-failure fixtures) and the core (POLYCALL_PREFIX, default
# /opt/polycall). Exit: 0 pass, 1 failure, 77 SKIPPED (a missing toolchain,
# or any skipped test, is never reported as success).
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
SBCL=${SBCL:-sbcl}
command -v "$SBCL" >/dev/null 2>&1 || { echo "SKIP: sbcl not found on PATH"; exit 77; }
"$SBCL" --noinform --non-interactive --eval '(require :asdf)' \
  --eval '(uiop:quit (if (asdf:find-system "cffi" nil) 0 3))' >/dev/null 2>&1 \
  || { echo "SKIP: CFFI is not available to ASDF (install cl-cffi or load Quicklisp)"; exit 77; }
. tests/real-core-env.sh
# paths cross to the core as UTF-8 (BINDING_ABI.md); SBCL encodes file names
# with the locale's external format
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf-8*|*utf8*|*UTF8*) ;;
  *) LC_ALL=C.UTF-8; export LC_ALL ;;
esac
SRC=${LISP_POLYCALL_SOURCE_DIR:-$REPO}
LISP_POLYCALL_REPO="$SRC"
LISP_POLYCALL_ASD="$SRC/lisp-polycall.asd"
# "<dir>/" registers that directory only; the trailing ":" keeps the default
# registry (where Debian's cl-cffi lives)
CL_SOURCE_REGISTRY="$SRC/:${CL_SOURCE_REGISTRY:-}"
export LISP_POLYCALL_REPO LISP_POLYCALL_ASD CL_SOURCE_REGISTRY
"$SBCL" --version
echo "lisp-polycall system from $SRC (CL_SOURCE_REGISTRY)"
"$SBCL" --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-system "lisp-polycall/tests")' \
  --eval '(format t "loaded ~A~%" (asdf:system-source-file "lisp-polycall"))' \
  --eval '(lisp-polycall/tests:run-tests-and-exit)'
