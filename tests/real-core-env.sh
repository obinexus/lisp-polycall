# Shared setup for the real-core test runners (sourced, POSIX sh).
#
# Locates the installed core (POLYCALL_PREFIX, default /opt/polycall, or a
# `polycall` already on PATH), builds the loader-failure fixtures, starts a
# `polycall start` runtime and a `polycall daemon` for polycall_call tests,
# and exports:
#   POLYCALL_CLI, POLYCALL_LIBRARY, POLYCALL_DEV_TOKEN (random test value),
#   POLYCALL_TEST_RPC_ENDPOINT (polycall start), POLYCALL_TEST_DAEMON_ENDPOINT
#   (polycall daemon), POLYCALL_TEST_FAKE_OLD, POLYCALL_TEST_FAKE_ABI2,
#   POLYCALL_TEST_TMP, POLYCALL_TEST_WINDOWS (1 under MSYS2 / Git Bash)
# Paths are exported in native form (C:/... on Windows). Everything runs on
# ephemeral loopback ports with state under POLYCALL_TEST_TMP. A missing core
# or compiler is a SKIP (exit 77), never a pass.

pc_skip() { echo "SKIP: $*"; exit 77; }

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) POLYCALL_TEST_WINDOWS=1 ;;
  *) POLYCALL_TEST_WINDOWS=0 ;;
esac
export POLYCALL_TEST_WINDOWS
pc_native() {
  if [ "$POLYCALL_TEST_WINDOWS" = 1 ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

PREFIX=${POLYCALL_PREFIX:-/opt/polycall}
if [ -x "$PREFIX/bin/polycall" ] || [ -x "$PREFIX/bin/polycall.exe" ]; then
  PATH="$PREFIX/bin:$PATH"
  LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export PATH LD_LIBRARY_PATH PKG_CONFIG_PATH
fi
POLYCALL_CLI=$(command -v polycall 2>/dev/null) || pc_skip "polycall CLI not found (install the core or set POLYCALL_PREFIX)"
POLYCALL_CLI=$(pc_native "$POLYCALL_CLI")
export POLYCALL_CLI
if [ -z "${POLYCALL_LIBRARY:-}" ]; then
  for pc_lib in "$PREFIX/lib/libpolycall.so.1" "$PREFIX/bin/libpolycall.dll" "$PREFIX/bin/polycall.dll"; do
    if [ -e "$pc_lib" ]; then POLYCALL_LIBRARY=$pc_lib; break; fi
  done
fi
[ -n "${POLYCALL_LIBRARY:-}" ] && [ -e "$POLYCALL_LIBRARY" ] || pc_skip "libpolycall not found (set POLYCALL_LIBRARY)"
POLYCALL_LIBRARY=$(pc_native "$POLYCALL_LIBRARY")
export POLYCALL_LIBRARY
CC=${CC:-cc}
command -v "$CC" >/dev/null 2>&1 || CC=gcc
command -v "$CC" >/dev/null 2>&1 || pc_skip "no C compiler for the loader-failure fixtures"

export POLYCALL_TELEMETRY=off
POLYCALL_DEV_TOKEN="qa-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
export POLYCALL_DEV_TOKEN

PC_TMP=$(mktemp -d "${TMPDIR:-/tmp}/polycall-test.XXXXXX")
POLYCALL_TEST_TMP=$(pc_native "$PC_TMP")
export POLYCALL_TEST_TMP
PC_RT_PID=""
PC_DAEMON_FILE=""
pc_cleanup() {
  [ -n "$PC_DAEMON_FILE" ] && "$POLYCALL_CLI" daemon stop --force -t 5000 "$PC_DAEMON_FILE" >/dev/null 2>&1
  [ -n "$PC_RT_PID" ] && kill "$PC_RT_PID" 2>/dev/null
  [ -n "$PC_RT_PID" ] && wait "$PC_RT_PID" 2>/dev/null
  rm -rf "$PC_TMP"
}
trap pc_cleanup EXIT INT TERM

# Loader-failure fixtures, named like the real library so they can stand in
# for it on the loader path: an old core without the ABI v1 symbols, and a
# core that reports ABI 2.
PC_FIXTURE=$(dirname "$0")/fixtures/fake_polycall.c
PC_LIBNAME=$(basename "$POLYCALL_LIBRARY")
if [ "$POLYCALL_TEST_WINDOWS" = 1 ]; then
  PC_SOFLAGS="-shared"
else
  PC_SOFLAGS="-shared -fPIC -Wl,-soname,libpolycall.so.1"
fi
mkdir -p "$PC_TMP/fake-old" "$PC_TMP/fake-abi2"
# shellcheck disable=SC2086
"$CC" $PC_SOFLAGS -DFAKE_OLD_CORE "$PC_FIXTURE" -o "$PC_TMP/fake-old/$PC_LIBNAME" \
  || { echo "FAIL: building fixture"; exit 1; }
# shellcheck disable=SC2086
"$CC" $PC_SOFLAGS -DFAKE_ABI=2 "$PC_FIXTURE" -o "$PC_TMP/fake-abi2/$PC_LIBNAME" \
  || { echo "FAIL: building fixture"; exit 1; }
POLYCALL_TEST_FAKE_OLD="$POLYCALL_TEST_TMP/fake-old/$PC_LIBNAME"
POLYCALL_TEST_FAKE_ABI2="$POLYCALL_TEST_TMP/fake-abi2/$PC_LIBNAME"
export POLYCALL_TEST_FAKE_OLD POLYCALL_TEST_FAKE_ABI2

# `polycall start` (foreground runtime) on an ephemeral port
"$POLYCALL_CLI" start --endpoint 127.0.0.1:0 --endpoint-file "$POLYCALL_TEST_TMP/rt.ep" \
  >"$PC_TMP/runtime.log" 2>&1 &
PC_RT_PID=$!
pc_i=0
while [ ! -s "$PC_TMP/rt.ep" ] && [ $pc_i -lt 100 ]; do sleep 0.1; pc_i=$((pc_i + 1)); done
[ -s "$PC_TMP/rt.ep" ] || { echo "FAIL: polycall start did not bind: $(cat "$PC_TMP/runtime.log")"; exit 1; }
POLYCALL_TEST_RPC_ENDPOINT=$(tr -d '\r\n' <"$PC_TMP/rt.ep")
export POLYCALL_TEST_RPC_ENDPOINT

# `polycall daemon` (detached, state next to its own Polycallfile) on an
# ephemeral port; stopped with the shared token by pc_cleanup
mkdir -p "$PC_TMP/daemon"
printf '%s\n' "# binding test daemon" "daemon_endpoint=127.0.0.1:0" \
  "auth_token_env=POLYCALL_DEV_TOKEN" >"$PC_TMP/daemon/Polycallfile"
PC_DAEMON_FILE="$POLYCALL_TEST_TMP/daemon/Polycallfile"
pc_out=$("$POLYCALL_CLI" --format json daemon start -t 15000 "$PC_DAEMON_FILE" 2>"$PC_TMP/daemon.err") \
  || { echo "FAIL: polycall daemon start: $(cat "$PC_TMP/daemon.err")"; exit 1; }
POLYCALL_TEST_DAEMON_ENDPOINT=$(printf '%s' "$pc_out" | sed -n 's/.*"endpoint":"\([^"]*\)".*/\1/p')
[ -n "$POLYCALL_TEST_DAEMON_ENDPOINT" ] || { echo "FAIL: polycall daemon start printed no endpoint: $pc_out"; exit 1; }
export POLYCALL_TEST_DAEMON_ENDPOINT

echo "core: $("$POLYCALL_CLI" --version) at $POLYCALL_LIBRARY; runtime at $POLYCALL_TEST_RPC_ENDPOINT; daemon at $POLYCALL_TEST_DAEMON_ENDPOINT"
