# @obinexusltd/lisp-polycall

Common Lisp CFFI binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5. The adapter maps
Lisp calls to the single core entry point:

```c
polycall_ffi_run_config(config_path, 1)
```

Configuration parsing, validation, networking, and runtime policy remain in
libpolycall. This package only marshals a UTF-8 configuration path and returns
the core status unchanged.

## Install the source package

```shell
npm install @obinexusltd/lisp-polycall
```

The npm package publishes the complete ASDF system, Common Lisp sources,
native adapter, headers, configuration, examples, and tests. Calling
`require('@obinexusltd/lisp-polycall')` returns absolute paths to the packaged
files.

## Requirements

- an ANSI Common Lisp implementation such as SBCL
- ASDF and [CFFI](https://cffi.common-lisp.dev/)
- libpolycall 1.5 development library and headers
- a C11 compiler and GNU Make

## Build

Build the standalone adapter archive without linking libpolycall:

```shell
make
```

Build the shared CFFI library by supplying the linker flags for libpolycall:

```shell
export POLYCALL_LDFLAGS='-L/path/to/lib -lpolycall'
make native
```

PowerShell uses the same variable:

```powershell
$env:POLYCALL_LDFLAGS = '-LC:\path\to\lib -lpolycall'
make native
```

Add this checkout to ASDF's source registry and load the system:

```lisp
(ql:quickload :cffi)
(asdf:load-asd #p"/path/to/lisp-polycall/lisp-polycall.asd")
(asdf:load-system "lisp-polycall")
```

Place the native library on the platform search path, or load it explicitly:

```lisp
(lisp-polycall:load-library #p"/absolute/path/to/liblisp_polycall.so")
```

## API

```lisp
(lisp-polycall:run-config "lisp-polycallrc")
(lisp-polycall:run-config-or-error "lisp-polycallrc")
```

- `run-config` returns the exact libpolycall status.
- `run-config-or-error` signals `polycall-error` for a non-zero status.
- Omitting the path uses `lisp-polycallrc`.
- `polycall-error-status` and `polycall-error-config-path` expose condition data.

See [`examples/basic.lisp`](examples/basic.lisp) for a runnable example.

## Verification

The default suite needs only a C compiler, Make, Node.js, and PowerShell on
Windows:

```shell
npm test
```

It verifies exact path forwarding, the required validation flag, status
propagation, thin-adapter constraints, ASDF metadata, and npm package
completeness.

With SBCL, ASDF, and CFFI installed, run the end-to-end smoke test:

```shell
npm run test:lisp
```

## Package layout

- `lisp-polycall.asd` — ASDF system and test system
- `src/*.lisp` — public Common Lisp API and CFFI definitions
- `src/lisp_polycall.c` — native forwarding adapter
- `include/` — adapter C header
- `generated/polycall/` — minimal generated core FFI declaration
- `examples/` and `tests/` — usage and verification

## Author and license

Copyright © 2026 Nnamdi Michael Okpala
<okpalan@protonmail.com>.

Released under the [MIT License](LICENSE).
