# Common Lisp adapter

The public API and CFFI declaration are in `lisp-polycall.lisp`. The native
adapter exports `lisp_polycall_run_config`, which forwards to
`polycall_ffi_run_config(config_path, 1)` and returns the status unchanged.

No configuration parsing or runtime policy belongs in this binding.
