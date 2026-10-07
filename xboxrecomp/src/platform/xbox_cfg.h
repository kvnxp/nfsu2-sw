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

/* Where nfsu2.cfg lives: the game directory (next to UDATA, where the
 * saves are), set once it is known. Before that -- and when nobody sets
 * it -- the working directory, as before. */
void xbox_CfgSetDir(const char *dir);

#ifdef __cplusplus
}
#endif
