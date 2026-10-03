# TODO — lisp-polycall

Status: Common Lisp/CFFI binding over the Polycall binding ABI v1 (libpolycall >= 1.1.0).

- [x] CFFI declarations of every `polycall.h` ABI v1 function; no C shim
- [x] Loader: `POLYCALL_LIBRARY`, then platform names; symbols resolved up front;
      clear `polycall-library-error` for a missing library, an old core, ABI /= 1
- [x] `run-config` keeps `polycall_ffi_run_config(path, 1)`; `polycall-call`; peers
- [x] `polycall-error` with status, `polycall_strerror` name, `polycall_last_error`
- [x] Real-core suite in SBCL 2.5.2 (Debian 13) incl. interop with the C CLI peer, `polycall daemon`, non-ASCII paths, loaded through CL_SOURCE_REGISTRY
- [ ] Run the suite on other implementations (CCL, ECL) -- the threaded tests use sb-thread
- [ ] Windows run (no SBCL on the QA host); macOS run (no macOS host)
- [ ] Publish `@obinexusltd/lisp-polycall` / submit to Quicklisp

Do not add configuration parsing or runtime policy here; adapt the core only.
