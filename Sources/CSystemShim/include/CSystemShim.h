// ABOUTME: C shim exposing system() to Swift.
// ABOUTME: Swift marks system() unavailable; this wraps it for pager invocation.

#ifndef C_SYSTEM_SHIM_H
#define C_SYSTEM_SHIM_H

/// Run a shell command via C system(). Inherits the controlling terminal.
int c_system(const char *command);

#endif
