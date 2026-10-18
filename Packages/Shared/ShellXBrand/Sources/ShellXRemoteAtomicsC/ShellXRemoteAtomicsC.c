#include "ShellXRemoteAtomicsC.h"

#include <stdatomic.h>

static atomic_bool shellx_bridge_tee_any_bound = false;

bool ShellXBridgeTeeAnyBound(void) {
    // Relaxed: a true result is rechecked under the registry lock.
    return atomic_load_explicit(&shellx_bridge_tee_any_bound, memory_order_relaxed);
}

void ShellXBridgeTeeSetAnyBound(bool value) {
    atomic_store_explicit(&shellx_bridge_tee_any_bound, value, memory_order_release);
}
