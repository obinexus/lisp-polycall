# lisp-polycall

Common Lisp binding for the [Polycall](https://github.com/obinexus/polycall)
core's **binding ABI v1** (`polycall.h`, libpolycall >= 1.1.0) through
[CFFI](https://cffi.common-lisp.dev/): configuration validation,
`polycall_rpc` calls and peer-to-peer nodes. ASDF system `lisp-polycall`;
npm source distribution `lisp-polycall` (not published yet).

CFFI calls libpolycall directly with the exact signatures from `polycall.h`
(there is no C shim to build). Configuration parsing, the wire protocols and
the peer transport stay in the core.

## Requirements

- SBCL (tested: 2.5.2 on Debian 13; threads are used for blocking receives)
  with ASDF, CFFI, babel and UIOP (Debian: `sbcl cl-cffi`; or Quicklisp)
- the Polycall core >= 1.1.0 installed (`libpolycall.so.1`, `polycall.dll` /
  `libpolycall.dll`, or `libpolycall.1.dylib`)

Tested: Linux x86_64 (Debian 13, SBCL 2.5.2, CFFI 0.24.1). The loader names
the Windows and macOS libraries, but neither platform has been tested (no SBCL
on the Windows QA host, no macOS host).

Install it like any ASDF system: put the checkout (or the unpacked npm
package) where ASDF looks — `~/common-lisp/`, a Quicklisp `local-projects/`
directory, or `CL_SOURCE_REGISTRY=/path/to/lisp-polycall/:` — then
`(asdf:load-system "lisp-polycall")`.

## Loading the library

`(lisp-polycall:load-library)` (called implicitly on first use) tries the
explicit pathname, then `POLYCALL_LIBRARY` (a path that does not exist is an
error), then the platform name through the OS loader search path. No package
or parent directory is searched. Every symbol is resolved up front: a missing
library, an old 1.0 core without the ABI v1 symbols, or
`polycall_ffi_abi_version() /= 1` signals `polycall-library-error` naming the
library and the problem.

## API

```lisp
(asdf:load-system "lisp-polycall")       ; or (asdf:load-asd #p"/path/to/lisp-polycall/lisp-polycall.asd") first
(use-package :lisp-polycall)

(abi-version)                              ; => 1
(polycall-version)                         ; => "1.1.0"
(run-config "lisp-polycallrc")             ; => 0, or the raw status: polycall_ffi_run_config(path, 1)
(run-config "lisp-polycallrc" nil)         ; run=0: unknown keys are warnings
(run-config-or-error "lisp-polycallrc")    ; signals POLYCALL-ERROR
(describe-config "lisp-polycallrc")        ; JSON

;; one polycall_rpc round trip to `polycall start` / `polycall daemon start`
(polycall-call "127.0.0.1:8084" "inventory" "get" :input "{\"item_id\":\"widget-a\"}" :timeout-ms 2000)

(with-peer (alpha "alpha" :bind "127.0.0.1:0" :token (uiop:getenv "POLYCALL_DEV_TOKEN"))
  (peer-register alpha "beta" "127.0.0.1:9002")
  (peer-send alpha "beta" "hello" :message-id "msg-1" :timeout-ms 5000) ; string -> UTF-8, or an octet vector
  (let ((m (peer-recv alpha :timeout-ms 5000)))                        ; or :infinite
    (values (message-sender m) (message-id m) (message-payload m)))     ; payload: (vector (unsigned-byte 8))
  (peer-ping alpha "beta") (peer-list alpha) (peer-health alpha)
  (peer-endpoint alpha) (peer-node-id alpha) (peer-unregister alpha "beta") (peer-cancel alpha))
```

Failures signal `polycall-error` with `polycall-error-status` (the
`POLYCALL_E_*` code, constants `+e-timeout+` ...), `polycall-error-name` (from
`polycall_strerror`), `polycall-error-detail` (`polycall_last_error` of this
thread) and `polycall-error-output` (the remote error object of a failed
`polycall-call`, or the needed size of a `peer-recv` whose `:capacity` was too
small — the message stays queued). A `peer-recv` blocked in one thread is woken
by `peer-cancel` or `peer-close` from another. Strings (paths, ids, endpoints,
JSON) cross as UTF-8; payloads are octet vectors (a string is sent UTF-8
encoded). Out-of-range timeouts signal `+e-invalid-argument+` before any call.

## Tests

`tests/run-real-core.sh` registers the checkout through `CL_SOURCE_REGISTRY`
(as an installed system is found), loads `lisp-polycall/tests` in SBCL and
runs `tests/real-core.lisp` against the **real installed core**: version/ABI,
a missing library, an old core and an ABI 2 core (child SBCL processes),
`run-config` (valid, missing, invalid, strict, TLS, non-ASCII path),
`polycall-call` against a live `polycall start` runtime and a
`polycall daemon`, timeout boundaries, two nodes both directions, payload
matrix (empty, UTF-8, binary + NUL, 1 MiB, 1 MiB + 1), registry ownership,
de-duplication, auth, dead peers, timeouts, small buffers, cancel and close
waking blocked receivers (threads), handle lifecycle, 8 concurrent sender
threads, and interop with a `polycall peer serve` C node. A missing SBCL,
CFFI or core, or any skipped test, is reported as SKIP (exit 77), never as
success. `LISP_POLYCALL_SOURCE_DIR` runs the suite on another copy (e.g. the
unpacked npm package); `(asdf:test-system "lisp-polycall")` signals an error
unless every test ran and passed (it needs the environment the runner sets up).

```sh
sh tests/run-real-core.sh     # core in /opt/polycall, or POLYCALL_PREFIX / POLYCALL_LIBRARY
```

## License

Copyright © 2026 Nnamdi Michael Okpala <okpalan@protonmail.com>. Released under
the [MIT License](LICENSE).
