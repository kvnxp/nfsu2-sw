#pragma once

/* A tiny KEY=value file (nfsu2.cfg) for the desktop settings the F1 menu
 * writes: SCALE, VSYNC, VOLUME and the KB_* key bindings. env always wins:
 * readers must check getenv() before this. The Switch never touches it (it
 * has its own env file) and never writes: no menu opens there. */

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void xbox_CfgInit(void);
int  xbox_CfgGet(const char *key, char *out, size_t cap);
void xbox_CfgSet(const char *key, const char *value);

#ifdef __cplusplus
}
#endif
