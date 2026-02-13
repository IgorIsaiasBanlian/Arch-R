/*
 * unset_preload.so — Prevent LD_PRELOAD inheritance to child processes
 *
 * Problem: ES uses system()/popen() to run shell commands (battery %, distro
 * version, etc.). With LD_PRELOAD=gl4es, every subprocess loads gl4es which
 * prints init messages to stdout. ES captures these as command output, causing
 * "BAT: 87LIBGL: Initialising gl4es..." on screen.
 *
 * Solution: This tiny library's constructor runs during process init (after
 * the dynamic linker has already loaded all LD_PRELOAD libraries into memory).
 * It removes LD_PRELOAD from the environment so child processes don't inherit
 * it. gl4es remains loaded in the current process (already memory-mapped).
 *
 * Usage: LD_PRELOAD="/usr/lib/gl4es/libGL.so.1 /usr/lib/unset_preload.so" cmd
 *
 * Build: aarch64-linux-gnu-gcc -shared -o unset_preload.so unset_preload.c
 */

#include <stdlib.h>

__attribute__((constructor))
static void unset_preload(void)
{
    unsetenv("LD_PRELOAD");
}
