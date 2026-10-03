#!/bin/sh
# lisp-polycall: load the ASDF system (CFFI straight onto libpolycall, no C
# shim) in SBCL and run tests/real-core.lisp against the REAL installed core.
#
#   sh tests/run-real-core.sh
#
# Needs sbcl with ASDF and CFFI (Debian: sbcl cl-cffi; or Quicklisp), a C
# compiler (loader-failure fixtures) and the core (POLYCALL_PREFIX, default
# /opt/polycall). Exit: 0 pass, 1 failure, 77 SKIPPED (a missing toolchain
# is never reported as success).
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
SBCL=${SBCL:-sbcl}
command -v "$SBCL" >/dev/null 2>&1 || { echo "SKIP: sbcl not found on PATH"; exit 77; }
"$SBCL" --noinform --non-interactive --eval '(require :asdf)' \
  --eval '(uiop:quit (if (asdf:find-system "cffi" nil) 0 3))' >/dev/null 2>&1 \
  || { echo "SKIP: CFFI is not available to ASDF (install cl-cffi or load Quicklisp)"; exit 77; }
. tests/real-core-env.sh
LISP_POLYCALL_REPO="$REPO"
LISP_POLYCALL_ASD="$REPO/lisp-polycall.asd"
export LISP_POLYCALL_REPO LISP_POLYCALL_ASD
"$SBCL" --version
"$SBCL" --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval "(asdf:load-asd \"$LISP_POLYCALL_ASD\")" \
  --eval '(asdf:test-system "lisp-polycall")'
