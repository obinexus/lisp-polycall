# Common Lisp tests

- `run-real-core.sh` — the real-core runner. Sources `real-core-env.sh`
  (locates the installed core, builds the loader-failure fixtures, starts a
  `polycall start` runtime, sets a random `POLYCALL_DEV_TOKEN`) and runs
  `(asdf:test-system "lisp-polycall")` in SBCL. Exit 77 = SKIPPED (no SBCL /
  CFFI / core), never success.
- `real-core.lisp` — prints PASS/FAIL/SKIP per test and exits 1 on any
  failure: library (version, ABI, strerror, per-thread last_error, missing
  library / old core / ABI 2 in child SBCL processes), config, call, peer
  (both directions, payload matrix, registry ownership, duplicate id, auth,
  dead peer, timeout, too-small buffer, cancel / close waking blocked
  receivers in threads, handle lifecycle, invalid ids, 8 concurrent sender
  threads with backpressure retries) and interop (`polycall peer serve` C
  node both directions, CLI `register` / `health`, `call` parity).
- `fixtures/fake_polycall.c` — loader-failure fixture only (old core, ABI 2).
- `package.test.js` — npm / ASDF / binding-manifest metadata (no Lisp).
