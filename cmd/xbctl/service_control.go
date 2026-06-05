package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func runPrivilegedCommand(name string, args ...string) error {
	if os.Geteuid() == 0 {
		return runCommand(name, args...)
	}
	if commandExists(name) && commandExists("sudo") {
		return runCommand("sudo", append([]string{name}, args...)...)
	}
	return fmt.Errorf("%s requires root privileges; run with sudo or as root", name)
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func detectInitSystem() initSystem {
	return detectInitSystemWith(commandExists, func(path string) bool {
		_, err := os.Stat(path)
		return err == nil
	})
}

func detectInitSystemWith(hasCommand func(string) bool, pathExists func(string) bool) initSystem {
	if hasCommand("systemctl") && pathExists("/run/systemd/system") {
		return initSystemSystemd
	}
	if hasCommand("rc-service") && hasCommand("rc-update") {
		return initSystemOpenRC
	}
	return initSystemUnknown
}

func serviceFilePath() string {
	if detectInitSystem() == initSystemOpenRC {
		return openRCServiceFilePath
	}
	return systemdServiceFilePath
}

func runServiceCommand(action string, extra ...string) error {
	switch detectInitSystem() {
	case initSystemSystemd:
		switch action {
		case "status":
			return runPrivilegedCommand("systemctl", append([]string{"status", systemdServiceName, "--no-pager"}, extra...)...)
		case "start", "stop", "restart", "enable", "disable":
			return runPrivilegedCommand("systemctl", append([]string{action, systemdServiceName}, extra...)...)
		default:
			return fmt.Errorf("unsupported service action: %s", action)
		}
	case initSystemOpenRC:
		switch action {
		case "status", "start", "stop", "restart":
			return runPrivilegedCommand("rc-service", append([]string{openRCServiceName, action}, extra...)...)
		case "enable":
			return runPrivilegedCommand("rc-update", append([]string{"add", openRCServiceName, "default"}, extra...)...)
		case "disable":
			return runPrivilegedCommand("rc-update", append([]string{"del", openRCServiceName, "default"}, extra...)...)
		default:
			return fmt.Errorf("unsupported service action: %s", action)
		}
	default:
		return errors.New("unsupported init system: need systemd or OpenRC")
	}
}

func runServiceLogs(args []string) error {
	switch detectInitSystem() {
	case initSystemSystemd:
		if len(args) == 0 {
			args = []string{"-f"}
		}
		return runPrivilegedCommand("journalctl", append([]string{"-u", systemdServiceName}, args...)...)
	case initSystemOpenRC:
		if len(args) == 0 {
			args = []string{"-n", "100", "-f"}
		}
		return runPrivilegedCommand("tail", append(args, "/var/log/mi-node.log", "/var/log/mi-node.err")...)
	default:
		return errors.New("unsupported init system: need systemd or OpenRC")
	}
}

func serviceState() string {
	switch detectInitSystem() {
	case initSystemSystemd:
		cmd := exec.Command("systemctl", "is-active", systemdServiceName)
		out, err := cmd.CombinedOutput()
		state := strings.TrimSpace(string(out))
		if state != "" {
			return state
		}
		if err != nil {
			return "unknown"
		}
		return state
	case initSystemOpenRC:
		if err := exec.Command("rc-service", openRCServiceName, "status").Run(); err == nil {
			return "running"
		}
		return "stopped"
	default:
		return "unknown"
	}
}

func regenerateServiceFile() error {
	switch detectInitSystem() {
	case initSystemOpenRC:
		return regenerateOpenRCServiceFile()
	default:
		return regenerateSystemdServiceFile()
	}
}

func regenerateSystemdServiceFile() error {
	unit := fmt.Sprintf(`[Unit]
Description=Mi Node Backend
Documentation=https://github.com/micah123321/mi-node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%s
EnvironmentFile=-%s
ExecStart=%s -c %s
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, defaultInstallRoot, defaultCredentialsPath, defaultBinaryPath, defaultConfigPath)
	return os.WriteFile(systemdServiceFilePath, []byte(unit), 0o644)
}

func regenerateOpenRCServiceFile() error {
	script := fmt.Sprintf(`#!/sbin/openrc-run

name="mi-node"
description="Mi Node Backend"
supervisor=supervise-daemon
command="%s"
command_args="-c %s"
command_user="root:root"
directory="%s"
pidfile="/run/mi-node.pid"
output_log="/var/log/mi-node.log"
error_log="/var/log/mi-node.err"
respawn_delay=5
respawn_max=0

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --mode 0755 "%s"
    checkpath --file --mode 0644 "${output_log}"
    checkpath --file --mode 0644 "${error_log}"
}

export_envs() {
    if [ -f "%s" ]; then
        while IFS='=' read -r key value; do
            case "${key}" in
                ""|\#*) continue ;;
            esac
            export "${key}=${value}"
        done < "%s"
    fi
}

start() {
    export_envs
    default_start
}
`, defaultBinaryPath, defaultConfigPath, defaultInstallRoot, defaultInstallRoot, defaultCredentialsPath, defaultCredentialsPath)
	return os.WriteFile(openRCServiceFilePath, []byte(script), 0o755)
}
