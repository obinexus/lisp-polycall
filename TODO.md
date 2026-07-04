# TODO — lisp-polycall

Status: implemented thin Common Lisp/CFFI adapter for libpolycall 1.5.

- [x] Publishable `@obinexusltd/lisp-polycall` npm source package
- [x] ASDF system with CFFI dependency
- [x] Raw-status API and typed `polycall-error` condition
- [x] UTF-8 string marshalling and explicit library loader
- [x] Exact `polycall_ffi_run_config(config_path, 1)` forwarding
- [x] Native forwarding test and Common Lisp smoke test
- [x] Thin-adapter source audit for Windows and POSIX shells
- [ ] Exercise the CFFI smoke test in release CI across Lisp implementations
- [ ] Publish signed platform-native artifacts

Do not add configuration parsing or runtime policy here; adapt the core only.
