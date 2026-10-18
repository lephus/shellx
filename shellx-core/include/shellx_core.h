#pragma once
/* shellx-core C ABI (K3). Thread-safe. */
#ifdef __cplusplus
extern "C" {
#endif

/* Calls `method` with `json_in` (UTF-8 JSON). Returns a NUL-terminated JSON
 * envelope: {"ok": ...} or {"error": {"code": ..., "message": ...}}.
 * The result is never NULL. The caller MUST release it with shellx_core_free. */
char *shellx_core_call(const char *method, const char *json_in);

/* Frees a string returned by shellx_core_call. NULL is allowed. */
void shellx_core_free(char *ptr);

#ifdef __cplusplus
}
#endif
