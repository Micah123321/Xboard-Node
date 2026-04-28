package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/micah123321/mi-node/internal/config"
)

func TestWriteRootConfigPreservesInstanceEgress(t *testing.T) {
	t.Setenv("MI_NODE_API_TOKEN", "token")
	path := t.TempDir() + "/config.yml"

	root := &config.RootConfig{
		Instances: []config.Config{
			{
				Panel: config.PanelConfig{
					URL:      "https://panel.example.com",
					TokenEnv: "MI_NODE_API_TOKEN",
					NodeID:   1,
				},
				Kernel: config.KernelConfig{
					Type:      "singbox",
					ConfigDir: "/etc/mi-node",
					Egress: config.EgressConfig{
						SOCKS5: config.SOCKS5EgressConfig{
							Address: "127.0.0.1",
							Port:    1080,
						},
					},
				},
				Log: config.LogConfig{Level: "info", Output: "stdout"},
			},
		},
	}

	if err := writeRootConfig(path, root); err != nil {
		t.Fatalf("writeRootConfig: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(data), "egress:") {
		t.Fatalf("written config does not contain egress:\n%s", data)
	}

	loaded, err := config.LoadRoot(path)
	if err != nil {
		t.Fatalf("LoadRoot: %v", err)
	}
	instances, err := loaded.NormalizeInstances()
	if err != nil {
		t.Fatalf("NormalizeInstances: %v", err)
	}
	if got := instances[0].Kernel.Egress.SOCKS5.Address; got != "127.0.0.1" {
		t.Fatalf("SOCKS5 address = %q, want 127.0.0.1", got)
	}
	if got := instances[0].Kernel.Egress.SOCKS5.Port; got != 1080 {
		t.Fatalf("SOCKS5 port = %d, want 1080", got)
	}
}

func TestRunConfigInitMergesInstancesAndPreservesInstallOptions(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.yml")
	credentialsPath := filepath.Join(dir, "credentials.env")
	metaPath := filepath.Join(dir, "install-meta.json")
	installRoot := filepath.Join(dir, "mi-node")

	if err := runConfigInit([]string{
		"--mode", "node",
		"--panel-url", "http://panel.example.com",
		"--node-id", "266",
		"--node-type", "trojan",
		"--kernel", "singbox",
		"--health-port", "65530",
		"--debug-port", "65531",
		"--token", "token-266",
		"--version", "test-version",
		"--output", configPath,
		"--credentials-out", credentialsPath,
		"--meta", metaPath,
		"--install-root", installRoot,
		"--gomemlimit", "128MiB",
		"--gogc", "50",
		"--cert-mode", "dns",
		"--cert-domain", "fxhk.example.com",
		"--cert-email", "admin@example.com",
		"--cert-http-port", "8080",
		"--cert-dns-provider", "cloudflare",
		"--cert-dns-env", "CF_API_TOKEN=secret-266",
		"--egress-socks5-address", "127.0.0.1",
		"--egress-socks5-port", "1080",
		"--egress-socks5-user", "user",
		"--egress-socks5-pass", "pass",
	}); err != nil {
		t.Fatalf("first config init: %v", err)
	}

	ssURI := "ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@127.0.0.1:8388"
	if err := runConfigInit([]string{
		"--config", configPath,
		"--output", configPath,
		"--credentials-in", credentialsPath,
		"--credentials-out", credentialsPath,
		"--meta", metaPath,
		"--mode", "node",
		"--panel-url", "http://panel.example.com",
		"--node-id", "267",
		"--kernel", "singbox",
		"--health-port", "65532",
		"--debug-port", "65533",
		"--token", "token-267",
		"--version", "test-version",
		"--install-root", installRoot,
		"--cert-mode", "http",
		"--cert-domain", "next.example.com",
		"--cert-http-port", "80",
		"--egress-shadowsocks-uri", ssURI,
	}); err != nil {
		t.Fatalf("second config init: %v", err)
	}

	root, err := loadWritableRootConfig(configPath)
	if err != nil {
		t.Fatalf("load writable config: %v", err)
	}
	instances := normalizeRootInstances(root)
	if got := len(instances); got != 2 {
		t.Fatalf("instance count = %d, want 2", got)
	}

	first := findInstanceByNodeID(t, instances, 266)
	second := findInstanceByNodeID(t, instances, 267)
	if first.Panel.TokenEnv == "" || second.Panel.TokenEnv == "" || first.Panel.TokenEnv == second.Panel.TokenEnv {
		t.Fatalf("token env keys are not unique: first=%q second=%q", first.Panel.TokenEnv, second.Panel.TokenEnv)
	}

	credentials, err := os.ReadFile(credentialsPath)
	if err != nil {
		t.Fatalf("read credentials: %v", err)
	}
	credentialsText := string(credentials)
	for _, want := range []string{
		first.Panel.TokenEnv + "=token-266",
		second.Panel.TokenEnv + "=token-267",
	} {
		if !strings.Contains(credentialsText, want) {
			t.Fatalf("credentials missing %q:\n%s", want, credentialsText)
		}
	}

	if first.HealthPort != 65530 || first.DebugPort != 65531 {
		t.Fatalf("first ports = health:%d debug:%d, want 65530/65531", first.HealthPort, first.DebugPort)
	}
	if first.Runtime.GoMemLimit != "128MiB" || first.Runtime.GoGCPercent != 50 {
		t.Fatalf("first runtime = %+v", first.Runtime)
	}
	if first.Cert.CertMode != "dns" || first.Cert.Domain != "fxhk.example.com" || first.Cert.DNSProvider != "cloudflare" {
		t.Fatalf("first cert = %+v", first.Cert)
	}
	if got := first.Cert.DNSEnv["CF_API_TOKEN"]; got != "secret-266" {
		t.Fatalf("first cert dns env = %q, want secret-266", got)
	}
	if first.Kernel.Egress.EnableDefaultRules == nil || !*first.Kernel.Egress.EnableDefaultRules {
		t.Fatal("first egress enable_default_rules was not written as true")
	}
	if first.Kernel.Egress.PreferIPv4 == nil || !*first.Kernel.Egress.PreferIPv4 {
		t.Fatal("first egress prefer_ipv4 was not written as true")
	}
	if first.Kernel.Egress.SOCKS5.Address != "127.0.0.1" || first.Kernel.Egress.SOCKS5.Port != 1080 {
		t.Fatalf("first socks5 = %+v", first.Kernel.Egress.SOCKS5)
	}
	if first.Kernel.Egress.SOCKS5.Username != "user" || first.Kernel.Egress.SOCKS5.Password != "pass" {
		t.Fatalf("first socks5 auth = %+v", first.Kernel.Egress.SOCKS5)
	}
	if second.Cert.CertMode != "http" || second.Cert.Domain != "next.example.com" || second.Cert.HTTPPort != 80 {
		t.Fatalf("second cert = %+v", second.Cert)
	}
	if second.Kernel.Egress.Shadowsocks.URI != ssURI {
		t.Fatalf("second shadowsocks URI = %q, want %q", second.Kernel.Egress.Shadowsocks.URI, ssURI)
	}

	t.Setenv(first.Panel.TokenEnv, "token-266")
	t.Setenv(second.Panel.TokenEnv, "token-267")
	loaded, err := config.LoadRoot(configPath)
	if err != nil {
		t.Fatalf("LoadRoot generated config: %v", err)
	}
	loadedInstances, err := loaded.NormalizeInstances()
	if err != nil {
		t.Fatalf("NormalizeInstances generated config: %v", err)
	}
	if got := len(loadedInstances); got != 2 {
		t.Fatalf("loaded instance count = %d, want 2", got)
	}

	metaData, err := os.ReadFile(metaPath)
	if err != nil {
		t.Fatalf("read meta: %v", err)
	}
	var meta installMeta
	if err := json.Unmarshal(metaData, &meta); err != nil {
		t.Fatalf("parse meta: %v\n%s", err, metaData)
	}
	if meta.InstanceCount != 2 {
		t.Fatalf("meta instance count = %d, want 2", meta.InstanceCount)
	}
	secondID, err := second.AutoInstanceID()
	if err != nil {
		t.Fatalf("second AutoInstanceID: %v", err)
	}
	if meta.LatestInstanceID != secondID {
		t.Fatalf("meta latest instance = %q, want %q", meta.LatestInstanceID, secondID)
	}
}

func TestRunEgressSetListClear(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.yml")
	metaPath := filepath.Join(dir, "install-meta.json")

	root := &config.RootConfig{
		Instances: []config.Config{
			testNodeConfig("http://panel.example.com", 266),
			testNodeConfig("http://panel.example.com", 322),
		},
	}
	if err := writeRootConfig(configPath, root); err != nil {
		t.Fatalf("write config: %v", err)
	}

	socksURL := "socks5://admin:%40secret@198.51.100.10:30601"
	if err := runEgress([]string{
		"set",
		"--config", configPath,
		"--meta", metaPath,
		"--node-id", "322",
		"--socks5-url", socksURL,
		"--no-restart",
	}); err != nil {
		t.Fatalf("egress set socks5: %v", err)
	}

	updated := loadTestInstances(t, configPath)
	node322 := findInstanceByNodeID(t, updated, 322)
	if node322.Kernel.Egress.SOCKS5.Address != "198.51.100.10" {
		t.Fatalf("socks5 address = %q", node322.Kernel.Egress.SOCKS5.Address)
	}
	if node322.Kernel.Egress.SOCKS5.Port != 30601 {
		t.Fatalf("socks5 port = %d", node322.Kernel.Egress.SOCKS5.Port)
	}
	if node322.Kernel.Egress.SOCKS5.Username != "admin" {
		t.Fatalf("socks5 username = %q", node322.Kernel.Egress.SOCKS5.Username)
	}
	if node322.Kernel.Egress.SOCKS5.Password != "@secret" {
		t.Fatalf("socks5 password was not URL-decoded: %q", node322.Kernel.Egress.SOCKS5.Password)
	}

	listOutput := captureStdout(t, func() error {
		return runEgress([]string{"list", "--config", configPath})
	})
	if !strings.Contains(listOutput, "socks5") || !strings.Contains(listOutput, "198.51.100.10:30601") {
		t.Fatalf("list output missing socks5 summary:\n%s", listOutput)
	}
	if strings.Contains(listOutput, "@secret") || strings.Contains(listOutput, "admin:") {
		t.Fatalf("list output leaked credentials:\n%s", listOutput)
	}

	ssURI := "ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@203.0.113.10:8388"
	if err := runEgress([]string{
		"set",
		"--config", configPath,
		"--meta", metaPath,
		"--node-id", "322",
		"--shadowsocks-uri", ssURI,
		"--no-restart",
	}); err != nil {
		t.Fatalf("egress set shadowsocks: %v", err)
	}
	updated = loadTestInstances(t, configPath)
	node322 = findInstanceByNodeID(t, updated, 322)
	if node322.Kernel.Egress.SOCKS5.Address != "" || node322.Kernel.Egress.SOCKS5.Port != 0 {
		t.Fatalf("socks5 was not cleared after shadowsocks switch: %+v", node322.Kernel.Egress.SOCKS5)
	}
	if node322.Kernel.Egress.Shadowsocks.URI != ssURI {
		t.Fatalf("shadowsocks uri = %q", node322.Kernel.Egress.Shadowsocks.URI)
	}

	listOutput = captureStdout(t, func() error {
		return runEgress([]string{"list", "--config", configPath})
	})
	if strings.Contains(listOutput, "YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==") {
		t.Fatalf("list output leaked shadowsocks credentials:\n%s", listOutput)
	}
	if !strings.Contains(listOutput, "203.0.113.10:8388") {
		t.Fatalf("list output missing sanitized shadowsocks upstream:\n%s", listOutput)
	}

	if err := runEgress([]string{
		"clear",
		"--config", configPath,
		"--meta", metaPath,
		"--node-id", "322",
		"--no-restart",
	}); err != nil {
		t.Fatalf("egress clear: %v", err)
	}
	updated = loadTestInstances(t, configPath)
	node322 = findInstanceByNodeID(t, updated, 322)
	if node322.Kernel.Egress.SOCKS5.Address != "" || node322.Kernel.Egress.Shadowsocks.URI != "" {
		t.Fatalf("egress was not cleared: %+v", node322.Kernel.Egress)
	}
}

func TestRunEgressRequiresUniqueTarget(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.yml")
	metaPath := filepath.Join(dir, "install-meta.json")
	root := &config.RootConfig{
		Instances: []config.Config{
			testNodeConfig("http://panel-a.example.com", 322),
			testNodeConfig("http://panel-b.example.com", 322),
		},
	}
	if err := writeRootConfig(configPath, root); err != nil {
		t.Fatalf("write config: %v", err)
	}

	err := runEgress([]string{
		"set",
		"--config", configPath,
		"--meta", metaPath,
		"--node-id", "322",
		"--socks5", "127.0.0.1:1080",
		"--no-restart",
	})
	if err == nil {
		t.Fatal("expected ambiguous node_id to fail")
	}
	if !strings.Contains(err.Error(), "multiple instances matched") {
		t.Fatalf("unexpected error: %v", err)
	}

	if err := runEgress([]string{
		"set",
		"--config", configPath,
		"--meta", metaPath,
		"--panel-url", "http://panel-b.example.com",
		"--node-id", "322",
		"--socks5", "127.0.0.1:1080",
		"--no-restart",
	}); err != nil {
		t.Fatalf("egress set with panel disambiguation: %v", err)
	}
	updated := loadTestInstances(t, configPath)
	node322PanelB := findInstanceByPanelAndNodeID(t, updated, "http://panel-b.example.com", 322)
	if node322PanelB.Kernel.Egress.SOCKS5.Address != "127.0.0.1" {
		t.Fatalf("panel-b socks5 address = %q", node322PanelB.Kernel.Egress.SOCKS5.Address)
	}
}

func findInstanceByNodeID(t *testing.T, instances []config.Config, nodeID int) config.Config {
	t.Helper()
	for _, inst := range instances {
		if inst.Panel.NodeID == nodeID {
			return inst
		}
	}
	t.Fatalf("node %d not found in %+v", nodeID, instances)
	return config.Config{}
}

func findInstanceByPanelAndNodeID(t *testing.T, instances []config.Config, panel string, nodeID int) config.Config {
	t.Helper()
	for _, inst := range instances {
		if inst.Panel.URL == panel && inst.Panel.NodeID == nodeID {
			return inst
		}
	}
	t.Fatalf("panel %s node %d not found in %+v", panel, nodeID, instances)
	return config.Config{}
}

func testNodeConfig(panelURL string, nodeID int) config.Config {
	return config.Config{
		Panel: config.PanelConfig{
			URL:      panelURL,
			TokenEnv: "TOKEN_ENV",
			NodeID:   nodeID,
		},
		Kernel: config.KernelConfig{
			Type:      "singbox",
			ConfigDir: "/etc/mi-node",
		},
		Log: config.LogConfig{Level: "info", Output: "stdout"},
	}
}

func loadTestInstances(t *testing.T, path string) []config.Config {
	t.Helper()
	root, err := loadWritableRootConfig(path)
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	return normalizeRootInstances(root)
}

func captureStdout(t *testing.T, fn func() error) string {
	t.Helper()
	original := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	runErr := fn()
	_ = w.Close()
	os.Stdout = original
	data, readErr := io.ReadAll(r)
	if readErr != nil {
		t.Fatalf("read stdout: %v", readErr)
	}
	if runErr != nil {
		t.Fatalf("captured function failed: %v", runErr)
	}
	return string(data)
}
