package main

import "testing"

func TestDetectInitSystemWithPrefersRunningSystemd(t *testing.T) {
	hasCommand := func(name string) bool {
		return name == "systemctl" || name == "rc-service" || name == "rc-update"
	}
	pathExists := func(path string) bool { return path == "/run/systemd/system" }

	if got := detectInitSystemWith(hasCommand, pathExists); got != initSystemSystemd {
		t.Fatalf("expected systemd, got %s", got)
	}
}

func TestDetectInitSystemWithFallsBackToOpenRC(t *testing.T) {
	hasCommand := func(name string) bool {
		return name == "systemctl" || name == "rc-service" || name == "rc-update"
	}
	pathExists := func(string) bool { return false }

	if got := detectInitSystemWith(hasCommand, pathExists); got != initSystemOpenRC {
		t.Fatalf("expected openrc, got %s", got)
	}
}

func TestDetectInitSystemWithRequiresOpenRCTools(t *testing.T) {
	hasCommand := func(name string) bool { return name == "rc-service" }
	pathExists := func(string) bool { return false }

	if got := detectInitSystemWith(hasCommand, pathExists); got != initSystemUnknown {
		t.Fatalf("expected unknown, got %s", got)
	}
}
