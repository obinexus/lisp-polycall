# lisp-polycall -- Common Lisp (CFFI) binding over the Polycall binding ABI v1.
# There is nothing to compile ahead of time: CFFI calls libpolycall directly.
#
#   make test     run tests/real-core.lisp in SBCL against the real core
SBCL ?= sbcl

.PHONY: all
all:
	@echo "nothing to build: load lisp-polycall.asd with ASDF (depends on cffi, babel, uiop)"

.PHONY: test
test:
	SBCL=$(SBCL) sh tests/run-real-core.sh
