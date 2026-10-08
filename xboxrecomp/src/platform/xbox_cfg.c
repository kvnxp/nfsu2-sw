/* The desktop settings file for the F1 menu: SCALE, VSYNC, VOLUME and the
 * KB_* key bindings, one KEY=value per line, '#' starts a comment, blank
 * lines are kept as written. Everything is in memory after xbox_CfgInit();
 * a set rewrites the whole file, which is small (a change comes from a
 * human pressing a key, not from a loop). getenv() is not consulted here:
 * callers check the environment first, so the file never overrides an
 * explicit variable. */
#include "xbox_cfg.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CFG_NAME "nfsu2.cfg"
#define CFG_MAX_LINES 64
#define CFG_MAX_LEN 128

static char   s_lines[CFG_MAX_LINES][CFG_MAX_LEN];
static int    s_nlines;
static int    s_inited;
static char   s_dir[4096];          /* game dir; empty = working directory */
static int    s_warned;

static void cfg_path(char *out, size_t cap)
{
    if (s_dir[0])
        snprintf(out, cap, "%s/%s", s_dir, CFG_NAME);
    else
        snprintf(out, cap, "%s", CFG_NAME);
}

void xbox_CfgSetDir(const char *dir)
{
    size_t n;
    char tmp[4096];
    if (!dir || !dir[0])
        return;
    snprintf(tmp, sizeof tmp, "%s", dir);
    /* No trailing separator ("C:\\" keeps its own, "/" stays "/"). */
    n = strlen(tmp);
    while (n > 1 && (tmp[n - 1] == '/' || tmp[n - 1] == '\\'))
        tmp[--n] = 0;
    if (s_inited && !strcmp(s_dir, tmp))
        return;                         /* same one: keep what is loaded */
    memcpy(s_dir, tmp, n + 1);
    /* A different directory than the one already loaded: start over, so a
     * file found earlier somewhere else does not shadow the real one. */
    if (s_inited) {
        s_inited = 0;
        s_nlines = 0;
    }
}

static void cfg_save(void)
{
    char path[4352];
    FILE *f;
    int i;
    cfg_path(path, sizeof path);
    f = fopen(path, "wb");
    if (!f) {
        if (!s_warned++) {
            s_warned = 1;
            fprintf(stderr, "[CFG] cannot write %s\n", path);
        }
        return;
    }
    fprintf(f, "# written by the F1 menu; KEY=value, '#' starts a comment\n");
    for (i = 0; i < s_nlines; i++)
        fprintf(f, "%s\n", s_lines[i]);
    fclose(f);
}

void xbox_CfgInit(void)
{
    FILE *f;
    char line[CFG_MAX_LEN];
    char path[4352];

    if (s_inited)
        return;
    s_inited = 1;
    s_nlines = 0;
    cfg_path(path, sizeof path);
    f = fopen(path, "rb");
    if (!f)
        return;
    while (s_nlines < CFG_MAX_LINES && fgets(line, sizeof line, f)) {
        size_t n = strlen(line);
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
            line[--n] = 0;
        memcpy(s_lines[s_nlines], line, n + 1);
        s_nlines++;
    }
    fclose(f);
}

int xbox_CfgGet(const char *key, char *out, size_t cap)
{
    size_t kl = strlen(key);
    int i;

    xbox_CfgInit();
    for (i = 0; i < s_nlines; i++) {
        const char *l = s_lines[i];
        if (!l[0] || l[0] == '#')
            continue;
        if (!strncmp(l, key, kl) && l[kl] == '=') {
            size_t n = strlen(l + kl + 1);
            if (n >= cap)
                n = cap - 1;
            if (n) memcpy(out, l + kl + 1, n);
            out[n] = 0;
            return 1;
        }
    }
    return 0;
}

void xbox_CfgSet(const char *key, const char *value)
{
    char line[CFG_MAX_LEN];
    size_t kl = strlen(key);
    int i;

    xbox_CfgInit();
    snprintf(line, sizeof line, "%s=%s", key, value);
    for (i = 0; i < s_nlines; i++) {
        const char *l = s_lines[i];
        if (l[0] && l[0] != '#' && !strncmp(l, key, kl) && l[kl] == '=') {
            memcpy(s_lines[i], line, strlen(line) + 1);
            cfg_save();
            return;
        }
    }
    if (s_nlines < CFG_MAX_LINES) {
        memcpy(s_lines[s_nlines], line, strlen(line) + 1);
        s_nlines++;
        cfg_save();
    }
}
