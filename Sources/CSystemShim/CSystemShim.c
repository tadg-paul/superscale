// ABOUTME: C shim exposing system() to Swift.
// ABOUTME: Swift marks system() unavailable; this wraps it for pager invocation.

#include <stdlib.h>
#include "CSystemShim.h"

int c_system(const char *command) {
    return system(command);
}
