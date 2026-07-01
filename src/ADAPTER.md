# Lisp adapter (scaffold)

Implement the Lisp adapter here. It must call across the FFI boundary only:

    status = polycall_ffi_run_config("lisp-polycallrc", /*run=*/1)

Return/raise a Lisp-native error when `status` is non-zero. Do not parse
config or duplicate any core logic. See ../../../docs/adapter-pattern.md.
