#ifndef RUNNER_DAEMON_RUNNER_H_
#define RUNNER_DAEMON_RUNNER_H_

#include <flutter/dart_project.h>

// A5b D3: runs the headless shellx-mux (one FlutterEngine, no window) and
// returns the process exit code when its message loop ends.
int RunDaemon(flutter::DartProject project);

#endif  // RUNNER_DAEMON_RUNNER_H_
