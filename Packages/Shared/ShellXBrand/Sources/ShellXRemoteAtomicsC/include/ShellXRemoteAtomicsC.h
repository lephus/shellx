#ifndef SHELLX_REMOTE_ATOMICS_C_H
#define SHELLX_REMOTE_ATOMICS_C_H

#include <stdbool.h>

/// Lock-free "is any terminal bound to the bridge" gate for the PTY output tee
/// (ShellXBridgeTee.consume runs on every surface's IO thread). C11 atomics,
/// because Swift's Synchronization.Atomic needs macOS 15 and the app targets 14.
bool ShellXBridgeTeeAnyBound(void);
void ShellXBridgeTeeSetAnyBound(bool value);

#endif
