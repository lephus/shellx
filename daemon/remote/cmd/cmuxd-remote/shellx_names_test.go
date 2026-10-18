package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ShellX runs next to an installed cmux on the same remote host, so the
// helper's runtime names must never collide with cmux's ~/.cmux tree,
// its per-uid /tmp socket directory, or its `cmux` busybox name.

func TestShellXPersistentDaemonDefaultRootIsUnderDotShellX(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("CMUX_REMOTE_DAEMON_ROOT", "")
	t.Setenv("CMUX_REMOTE_DAEMON_SOCKET_DIR", "")

	paths, err := persistentDaemonPathsForSlot("shellx-slot")
	if err != nil {
		t.Fatalf("persistentDaemonPathsForSlot returned error: %v", err)
	}
	wantPrefix := filepath.Join(home, ".shellx", "daemon") + string(filepath.Separator)
	if !strings.HasPrefix(paths.root, wantPrefix) {
		t.Fatalf("root = %q, want under %q", paths.root, wantPrefix)
	}
	if strings.Contains(paths.root, ".cmux") {
		t.Fatalf("root %q must not use cmux's directory", paths.root)
	}
	wantSocketDir := filepath.Join("/tmp", fmt.Sprintf("shellx-remote-%d", os.Getuid()))
	if filepath.Dir(paths.socket) != wantSocketDir {
		t.Fatalf("socket dir = %q, want %q", filepath.Dir(paths.socket), wantSocketDir)
	}
	if base := filepath.Base(paths.socket); !strings.HasPrefix(base, "shellx-") || strings.Contains(base, "cmux") {
		t.Fatalf("socket name = %q, want a shellx- name", base)
	}
}

func TestShellXPersistentDaemonSocketOverrideChildIsShellXNamed(t *testing.T) {
	socketParent := t.TempDir()
	t.Setenv("CMUX_REMOTE_DAEMON_ROOT", filepath.Join(t.TempDir(), "daemon-root"))
	t.Setenv("CMUX_REMOTE_DAEMON_SOCKET_DIR", socketParent)

	paths, err := persistentDaemonPathsForSlot("override-slot")
	if err != nil {
		t.Fatalf("persistentDaemonPathsForSlot returned error: %v", err)
	}
	want := filepath.Join(socketParent, fmt.Sprintf("shellx-remote-%d", os.Getuid()))
	if filepath.Dir(paths.socket) != want {
		t.Fatalf("socket dir = %q, want %q", filepath.Dir(paths.socket), want)
	}
}

func TestShellXBusyboxNameEntersCLIMode(t *testing.T) {
	cases := []struct {
		argv0 string
		args  []string
		want  bool
	}{
		{"shellx", nil, true},
		{"/home/dev/.shellx/bin/shellx", []string{"ping"}, true},
		{"shellx-remote", []string{"ping"}, true},
		{"/home/dev/.shellx/bin/shellx-remote/1.0.0/linux-amd64/shellx-remote", []string{"serve", "--stdio"}, false},
		{"shellx-remote", []string{"version"}, false},
		{"shellx-remote", nil, false},
		// cmux's names belong to cmux's own helper.
		{"cmux", []string{"ping"}, false},
		{"cmuxd-remote", []string{"ping"}, false},
	}
	for _, tc := range cases {
		if got := shouldRunCLIForInvocation(tc.argv0, tc.args); got != tc.want {
			t.Errorf("shouldRunCLIForInvocation(%q, %q) = %v, want %v", tc.argv0, tc.args, got, tc.want)
		}
	}
}

func TestShellXHelloNamesTheHelper(t *testing.T) {
	input := strings.NewReader(`{"id":1,"method":"hello","params":{}}` + "\n")
	var out bytes.Buffer
	if code := run([]string{"serve", "--stdio"}, input, &out, newNotifyingBuffer()); code != 0 {
		t.Fatalf("run serve exit code = %d, want 0", code)
	}
	var response struct {
		OK     bool           `json:"ok"`
		Result map[string]any `json:"result"`
	}
	if err := json.Unmarshal([]byte(strings.SplitN(out.String(), "\n", 2)[0]), &response); err != nil {
		t.Fatalf("decode hello: %v (%q)", err, out.String())
	}
	if !response.OK || response.Result["name"] != "shellx-remote" {
		t.Fatalf("hello = %+v, want name shellx-remote", response)
	}
}

func TestShellXRelayAndCLIPathsAreUnderDotShellX(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dot := filepath.Join(home, ".shellx")

	if got := claudeHookLogPath(); got != filepath.Join(dot, "claude-hook.log") {
		t.Errorf("claudeHookLogPath = %q", got)
	}
	if got := claudeSettingsCacheDir(); got != filepath.Join(dot, "claude-settings") {
		t.Errorf("claudeSettingsCacheDir = %q", got)
	}
	cli, err := claudeHookInstalledCmuxBinary()
	if err != nil || cli != filepath.Join(dot, "bin", "shellx") {
		t.Errorf("claudeHookInstalledCmuxBinary = %q, %v; want ~/.shellx/bin/shellx", cli, err)
	}
	lease, err := persistentDaemonRelayPath(51000, ".slot")
	if err != nil || lease != filepath.Join(dot, "relay", "51000.slot") {
		t.Errorf("persistentDaemonRelayPath = %q, %v", lease, err)
	}
	signals, err := tmuxWaitForSignalDirectory()
	if err != nil || signals != filepath.Join(dot, "wait-for") {
		t.Errorf("tmuxWaitForSignalDirectory = %q, %v", signals, err)
	}

	if err := os.MkdirAll(filepath.Join(home, ".cmux"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".cmux", "socket_addr"), []byte("127.0.0.1:1111"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := readSocketAddrFile(); got != "" {
		t.Fatalf("readSocketAddrFile read cmux's relay address %q", got)
	}
	if err := os.WriteFile(filepath.Join(dot, "socket_addr"), []byte("127.0.0.1:2222\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := readSocketAddrFile(); got != "127.0.0.1:2222" {
		t.Fatalf("readSocketAddrFile = %q, want the ShellX relay address", got)
	}
}
