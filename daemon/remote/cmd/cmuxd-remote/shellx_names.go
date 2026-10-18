package main

// ShellX runtime names on the remote host. ShellX runs next to an installed
// cmux, so its helper never shares a directory, socket or CLI name with
// cmux's helper (its ~/.cmux tree, its per-uid /tmp socket directory, its
// `cmux` busybox name). The Go package directory and module path stay
// upstream's internal identifiers.
const (
	// remoteHelperName is the binary name, the hello `name`, and the prefix
	// of the per-user socket directory /tmp/shellx-remote-<uid>.
	remoteHelperName = "shellx-remote"
	// remoteCLIName is the busybox argv[0] that enters CLI mode
	// (~/.shellx/bin/shellx on the remote host).
	remoteCLIName = "shellx"
	// remoteStateDirName is $HOME/.shellx: daemon/, relay/, bin/,
	// socket_addr, wait-for/, claude-settings/, claude-hook.log.
	remoteStateDirName = ".shellx"
)
