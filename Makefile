CC ?= gcc
AR ?= ar
SBCL ?= sbcl

CPPFLAGS ?=
CPPFLAGS += -Iinclude -Igenerated
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
SHARED_CFLAGS ?= -fPIC

BUILD_DIR := build
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/lisp_polycall.o
STATIC_LIB := $(LIB_DIR)/liblisp_polycall.a
TEST_BIN := $(BUILD_DIR)/lisp_polycall_adapter_test

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
NATIVE_LIB := $(LIB_DIR)/lisp_polycall.dll
MOCK_NATIVE_LIB := $(BUILD_DIR)/lisp_polycall.dll
EXPORT_FILE := src/lisp_polycall.def
TEST_BIN := $(TEST_BIN)$(EXE_EXT)
else
EXPORT_FILE :=
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
NATIVE_LIB := $(LIB_DIR)/liblisp_polycall.dylib
MOCK_NATIVE_LIB := $(BUILD_DIR)/liblisp_polycall.dylib
else
NATIVE_LIB := $(LIB_DIR)/liblisp_polycall.so
MOCK_NATIVE_LIB := $(BUILD_DIR)/liblisp_polycall.so
endif
endif

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

$(BUILD_DIR) $(LIB_DIR):
ifeq ($(OS),Windows_NT)
	@if not exist "$@" mkdir "$@"
else
	@mkdir -p $@
endif

$(ADAPTER_OBJ): src/lisp_polycall.c include/lisp_polycall.h generated/polycall/polycall_ffi.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(TEST_BIN): src/lisp_polycall.c tests/polycall_ffi_mock.c tests/lisp_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(TEST_BIN)
	$(TEST_BIN)

.PHONY: native
native: | $(LIB_DIR)
ifeq ($(OS),Windows_NT)
	@if "$(strip $(POLYCALL_LDFLAGS))"=="" (echo Set POLYCALL_LDFLAGS to the libpolycall v1.5 linker flags & exit /b 2)
else
	@test -n "$(POLYCALL_LDFLAGS)" || (echo "Set POLYCALL_LDFLAGS to the libpolycall v1.5 linker flags" && exit 2)
endif
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SHARED_CFLAGS) \
		-DLISP_POLYCALL_BUILD_SHARED -shared src/lisp_polycall.c \
		$(EXPORT_FILE) $(POLYCALL_LDFLAGS) -o $(NATIVE_LIB)

$(MOCK_NATIVE_LIB): src/lisp_polycall.c src/lisp_polycall.def tests/polycall_ffi_mock.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $(SHARED_CFLAGS) \
		-DLISP_POLYCALL_BUILD_SHARED -shared src/lisp_polycall.c \
		$(EXPORT_FILE) tests/polycall_ffi_mock.c -o $@

.PHONY: test-lisp
test-lisp: $(MOCK_NATIVE_LIB)
ifeq ($(OS),Windows_NT)
	@set "PATH=$(abspath $(BUILD_DIR));%PATH%" && $(SBCL) --non-interactive \
		--eval "(require :asdf)" \
		--eval "(asdf:load-asd #p\"$(abspath lisp-polycall.asd)\")" \
		--eval "(asdf:test-system \"lisp-polycall\")"
else
	LD_LIBRARY_PATH="$(abspath $(BUILD_DIR)):$$LD_LIBRARY_PATH" $(SBCL) --non-interactive \
		--eval '(require :asdf)' \
		--eval '(asdf:load-asd #p"$(abspath lisp-polycall.asd)")' \
		--eval '(asdf:test-system "lisp-polycall")'
endif

.PHONY: verify-dry
verify-dry:
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-dry.ps1
else
	sh scripts/verify-dry.sh
endif

.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@if exist "$(BUILD_DIR)" rmdir /s /q "$(BUILD_DIR)"
	@if exist "$(LIB_DIR)" rmdir /s /q "$(LIB_DIR)"
else
	rm -rf $(BUILD_DIR) $(LIB_DIR)
endif

-include $(ADAPTER_OBJ:.o=.d)
