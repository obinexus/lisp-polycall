#ifndef LISP_POLYCALL_H
#define LISP_POLYCALL_H

#include <stdint.h>

#if defined(_WIN32) && defined(LISP_POLYCALL_BUILD_SHARED)
#define LISP_POLYCALL_API __declspec(dllexport)
#elif defined(__GNUC__) && defined(LISP_POLYCALL_BUILD_SHARED)
#define LISP_POLYCALL_API __attribute__((visibility("default")))
#else
#define LISP_POLYCALL_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

LISP_POLYCALL_API int32_t lisp_polycall_run_config(const char *config_path);

#ifdef __cplusplus
}
#endif

#endif
