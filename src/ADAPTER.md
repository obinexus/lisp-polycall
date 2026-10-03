# Common Lisp adapter

`lisp-polycall.lisp` declares the binding ABI v1 functions from `polycall.h`
with `cffi:defcfun` and calls libpolycall directly -- there is no C shim.
`load-library` honours `POLYCALL_LIBRARY`, then the platform library name,
resolves every symbol up front and checks `polycall_ffi_abi_version() == 1`.

Strings cross as NUL-terminated UTF-8, payloads as `(pointer, length)` octet
buffers, handles as int32; outputs go into caller-owned foreign buffers that
this binding frees. `run-config` keeps the documented contract:
`polycall_ffi_run_config(path, 1)` with the status returned unchanged.

No configuration parsing or runtime policy belongs here; adapt the core only.
