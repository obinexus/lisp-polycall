# Common Lisp tests

- `run-real-core.sh` — the real-core runner. Sources `real-core-env.sh`
  (locates the installed core, builds the loader-failure fixtures, starts a
  `polycall start` runtime and a `polycall daemon` on ephemeral ports, sets a
  random `POLYCALL_DEV_TOKEN`), registers the source directory through
  `CL_SOURCE_REGISTRY`, loads `lisp-polycall/tests` and calls
  `run-tests-and-exit` in SBCL. Exit 77 = SKIPPED (no SBCL / CFFI / core, or
  any skipped test), never success.
- `real-core.lisp` — prints PASS/FAIL/SKIP per test: library (version, ABI,
  ASDF found the system under test, strerror, per-thread last_error, missing
  library / old core / ABI 2 in child SBCL processes), config (incl.
  non-ASCII path), call (incl. `polycall daemon` and timeout boundaries),
  peer (both directions, payload matrix, registry ownership, duplicate id,
  auth, dead peer, timeout, too-small buffer, cancel / close waking blocked
  receivers in threads, handle lifecycle, invalid ids, 8 concurrent sender
  threads with backpressure retries) and interop (`polycall peer serve` C
  node both directions, CLI `register` / `health`, `call` parity).
- `fixtures/fake_polycall.c` — loader-failure fixture only (old core, ABI 2).
- `package.test.js` — npm / ASDF / binding-manifest metadata (no Lisp).
