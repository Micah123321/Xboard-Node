package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTemp(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func ssURI(method, password, host string, port int) string {
	userInfo := base64.StdEncoding.EncodeToString([]byte(method + ":" + password))
	return fmt.Sprintf("ss://%s@%s:%d", userInfo, host, port)
}

func TestLoad_ValidConfig(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://panel.example.com"
  token: "secret-token"
  node_id: 5
  node_type: "v2ray"
kernel:
  type: singbox
  log_level: warn
log:
  level: debug
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Panel.URL != "https://panel.example.com" {
		t.Errorf("url: got %q", cfg.Panel.URL)
	}
	if cfg.Panel.Token != "secret-token" {
		t.Errorf("token: got %q", cfg.Panel.Token)
	}
	if cfg.Panel.NodeID != 5 {
		t.Errorf("node_id: got %d", cfg.Panel.NodeID)
	}
	if cfg.Panel.NodeType != "v2ray" {
		t.Errorf("node_type: got %q", cfg.Panel.NodeType)
	}
	if cfg.Kernel.Type != "singbox" {
		t.Errorf("kernel.type: got %q", cfg.Kernel.Type)
	}
	if cfg.Log.Level != "debug" {
		t.Errorf("log.level: got %q", cfg.Log.Level)
	}
}

func TestLoad_Defaults(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://panel.example.com"
  token: "tok"
  node_id: 1
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Kernel.Type != "singbox" {
		t.Errorf("default kernel.type: got %q, want singbox", cfg.Kernel.Type)
	}
	if cfg.Kernel.ConfigDir != "/etc/mi-node" {
		t.Errorf("default config_dir: got %q", cfg.Kernel.ConfigDir)
	}
	if cfg.Kernel.LogLevel != "warn" {
		t.Errorf("default kernel log_level: got %q, want warn", cfg.Kernel.LogLevel)
	}
	if cfg.Log.Level != "info" {
		t.Errorf("default log.level: got %q, want info", cfg.Log.Level)
	}
	if cfg.Log.Output != "stdout" {
		t.Errorf("default log.output: got %q, want stdout", cfg.Log.Output)
	}
	if cfg.Cert.HTTPPort != 80 {
		t.Errorf("default http_port: got %d, want 80", cfg.Cert.HTTPPort)
	}
	if cfg.DebugPort != 0 {
		t.Errorf("default debug_port: got %d, want 0", cfg.DebugPort)
	}
	expectedCertDir := filepath.Join("/etc/mi-node", "certs")
	if cfg.Cert.CertDir != expectedCertDir {
		t.Errorf("default cert_dir: got %q, want %q", cfg.Cert.CertDir, expectedCertDir)
	}
	if !cfg.Kernel.Egress.DefaultRulesEnabled() {
		t.Error("expected egress.enable_default_rules to default to true")
	}
	if !cfg.Kernel.Egress.IPv4Preferred() {
		t.Error("expected egress.prefer_ipv4 to default to true")
	}
}

func TestLoad_MissingURL(t *testing.T) {
	path := writeTemp(t, `
panel:
  token: "tok"
  node_id: 1
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for missing url")
	}
}

func TestLoad_MissingToken(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  node_id: 1
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for missing token")
	}
}

func TestLoad_InvalidNodeID(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 0
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for node_id=0")
	}
}

func TestLoad_NegativeNodeID(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: -1
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for negative node_id")
	}
}

func TestLoad_InvalidKernelType(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  type: "invalid"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for invalid kernel type")
	}
}

func TestLoad_XrayKernel(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  type: xray
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Kernel.Type != "xray" {
		t.Errorf("kernel.type: got %q, want xray", cfg.Kernel.Type)
	}
}

func TestLoad_AutoTLS_NoDomain(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  auto_tls: true
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for auto_tls without domain")
	}
}

func TestLoad_AutoTLS_WithDomain(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  auto_tls: true
  domain: "node.example.com"
  email: "admin@example.com"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Cert.AutoTLS {
		t.Error("auto_tls should be true")
	}
	if cfg.Cert.Domain != "node.example.com" {
		t.Errorf("domain: got %q", cfg.Cert.Domain)
	}
}

func TestLoad_CertModeHTTP_WithDomain(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "http"
  domain: "node.example.com"
  email: "admin@example.com"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Cert.ResolveMode() != "http" {
		t.Fatalf("ResolveMode: got %q, want %q", cfg.Cert.ResolveMode(), "http")
	}
	if cfg.Cert.Domain != "node.example.com" {
		t.Errorf("domain: got %q", cfg.Cert.Domain)
	}
}

func TestLoad_CertModeHTTP_NoDomain(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "http"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for cert_mode=http without domain")
	}
}

func TestLoad_CertModeDNS_NoProvider(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "dns"
  domain: "node.example.com"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for cert_mode=dns without dns_provider")
	}
}

func TestLoad_CertModeDNS_WithProvider(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "dns"
  domain: "node.example.com"
  dns_provider: "cloudflare"
  dns_env:
    CF_API_TOKEN: "token"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Cert.ResolveMode() != "dns" {
		t.Fatalf("ResolveMode: got %q, want %q", cfg.Cert.ResolveMode(), "dns")
	}
	if cfg.Cert.DNSProvider != "cloudflare" {
		t.Errorf("dns_provider: got %q", cfg.Cert.DNSProvider)
	}
}

func TestLoad_InvalidCertMode(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "invalid"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for invalid cert_mode")
	}
}

func TestLoad_FileCertRequiresKey(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_mode: "file"
  cert_file: "/custom/cert.pem"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for file cert without key")
	}
}

func TestLoad_FileNotFound(t *testing.T) {
	_, err := Load("/nonexistent/path/config.yaml")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestLoad_InvalidYAML(t *testing.T) {
	path := writeTemp(t, "{{{{invalid yaml}}}")
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for invalid YAML")
	}
}

func TestLoad_CustomCert(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
cert:
  cert_file: "/custom/cert.pem"
  key_file: "/custom/key.pem"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Cert.CertFile != "/custom/cert.pem" {
		t.Errorf("cert_file: got %q", cfg.Cert.CertFile)
	}
	if cfg.Cert.KeyFile != "/custom/key.pem" {
		t.Errorf("key_file: got %q", cfg.Cert.KeyFile)
	}
}

func TestLoad_CustomIntervals(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
node:
  push_interval: 30
  pull_interval: 60
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Node.PushInterval != 30 {
		t.Errorf("push_interval: got %d", cfg.Node.PushInterval)
	}
	if cfg.Node.PullInterval != 60 {
		t.Errorf("pull_interval: got %d", cfg.Node.PullInterval)
	}
}

func TestLoad_DefaultTickerIntervals(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Node.TrackInterval != 10 {
		t.Fatalf("track_interval: got %d, want 10", cfg.Node.TrackInterval)
	}
	if cfg.Node.DeviceReportInterval != 30 {
		t.Fatalf("device_report_interval: got %d, want 30", cfg.Node.DeviceReportInterval)
	}
	if cfg.WS.StatusInterval != 10 {
		t.Fatalf("ws.status_interval: got %d, want 10", cfg.WS.StatusInterval)
	}
	if cfg.WS.HandshakeTimeout != 15 {
		t.Fatalf("ws.handshake_timeout: got %d, want 15", cfg.WS.HandshakeTimeout)
	}
	if cfg.WS.BackoffInitial != 1 {
		t.Fatalf("ws.backoff_initial: got %d, want 1", cfg.WS.BackoffInitial)
	}
	if cfg.WS.BackoffMax != 60 {
		t.Fatalf("ws.backoff_max: got %d, want 60", cfg.WS.BackoffMax)
	}
	if cfg.WS.DiscoveryInterval != 300 {
		t.Fatalf("ws.discovery_interval: got %d, want 300", cfg.WS.DiscoveryInterval)
	}
	if cfg.Node.LowJitterDisableDeviceReport {
		t.Fatal("expected low_jitter_disable_device_report to default to false")
	}
	if cfg.Kernel.LowJitterDisableDeviceGate {
		t.Fatal("expected low_jitter_disable_device_gate to default to false")
	}
}

func TestLoad_LowJitterToggles(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
node:
  low_jitter_disable_device_report: true
kernel:
  low_jitter_disable_device_gate: true
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Node.LowJitterDisableDeviceReport {
		t.Fatal("expected low_jitter_disable_device_report to be true")
	}
	if !cfg.Kernel.LowJitterDisableDeviceGate {
		t.Fatal("expected low_jitter_disable_device_gate to be true")
	}
}

func TestLoad_NegativeTickerIntervals(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
node:
  track_interval: -1
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for negative track_interval")
	}
	if !strings.Contains(err.Error(), "node.track_interval must not be negative") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoad_DebugPort(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
debug_port: 18080
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.DebugPort != 18080 {
		t.Fatalf("debug_port: got %d, want 18080", cfg.DebugPort)
	}
}

func TestLoad_DebugPortNegative(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
debug_port: -1
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for negative debug_port")
	}
	if !strings.Contains(err.Error(), "debug_port must not be negative") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoad_EgressSOCKS5_WithAuth(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    socks5:
      address: "127.0.0.1"
      port: 1080
      username: "user"
      password: "pass"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Kernel.Egress.ProxyEnabled() {
		t.Fatal("expected SOCKS5 proxy to be enabled")
	}
	if cfg.Kernel.Egress.DefaultOutboundTag() != DefaultSOCKS5ProxyTag {
		t.Fatalf("DefaultOutboundTag: got %q, want %q", cfg.Kernel.Egress.DefaultOutboundTag(), DefaultSOCKS5ProxyTag)
	}
}

func TestLoad_EgressShadowsocks_Traditional(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      uri: "`+ssURI("aes-128-gcm", "test-password", "127.0.0.1", 8388)+`"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Kernel.Egress.ShadowsocksEnabled() {
		t.Fatal("expected Shadowsocks proxy to be enabled")
	}
	if cfg.Kernel.Egress.DefaultOutboundTag() != DefaultShadowsocksProxyTag {
		t.Fatalf("DefaultOutboundTag: got %q, want %q", cfg.Kernel.Egress.DefaultOutboundTag(), DefaultShadowsocksProxyTag)
	}
}

func TestLoad_EgressShadowsocks_2022(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      uri: "ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206ODhvMGZwK3BBV29XS3ZrRGUydWhxek4zcDE3Uk5mQzdhSE0wVldJTUtuZz06UnlObkhsZ3lLT3ZKVzRCWVY5TnhWMDlMWkhnWGM1Ui9wamxKSjRPR3QyND0=@38.182.122.32:37605?type=tcp#93m0pjsu"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Kernel.Egress.ShadowsocksEnabled() {
		t.Fatal("expected Shadowsocks proxy to be enabled")
	}
	if cfg.Kernel.Egress.Shadowsocks.Address != "38.182.122.32" {
		t.Fatalf("address: got %q", cfg.Kernel.Egress.Shadowsocks.Address)
	}
	if cfg.Kernel.Egress.Shadowsocks.Port != 37605 {
		t.Fatalf("port: got %d", cfg.Kernel.Egress.Shadowsocks.Port)
	}
}

func TestLoad_EgressSOCKS5_MissingPort(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    socks5:
      address: "127.0.0.1"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for socks5 address without port")
	}
}

func TestLoad_EgressSOCKS5_PartialAuth(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    socks5:
      address: "127.0.0.1"
      port: 1080
      username: "user"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for partial socks5 authentication")
	}
}

func TestLoad_EgressShadowsocks_LegacyFieldsRejected(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      address: "127.0.0.1"
      port: 8388
      method: "aes-128-gcm"
      password: "test-password"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for legacy shadowsocks fields")
	}
	if !strings.Contains(err.Error(), "egress.shadowsocks.address is no longer supported") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoad_EgressShadowsocks_Invalid2022Password(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      uri: "`+ssURI("2022-blake3-aes-128-gcm", "not-base64", "127.0.0.1", 8388)+`"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for invalid shadowsocks 2022 password")
	}
}

func TestLoad_EgressShadowsocks_InvalidTraditionalMethod(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      uri: "`+ssURI("aes-129-gcm", "test-password", "127.0.0.1", 8388)+`"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for invalid traditional shadowsocks method")
	}
	if !strings.Contains(err.Error(), `unsupported egress.shadowsocks.method "aes-129-gcm"`) {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoad_EgressShadowsocks_AES192GCM_XrayRejected(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  type: "xray"
  egress:
    shadowsocks:
      uri: "`+ssURI("aes-192-gcm", "test-password", "127.0.0.1", 8388)+`"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for xray + aes-192-gcm")
	}
	if !strings.Contains(err.Error(), `egress.shadowsocks.method "aes-192-gcm" is not supported when kernel.type is "xray"`) {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoad_EgressShadowsocks_AES192GCM_SingboxAccepted(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  type: "singbox"
  egress:
    shadowsocks:
      uri: "`+ssURI("aes-192-gcm", "test-password", "127.0.0.1", 8388)+`"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Kernel.Egress.ShadowsocksEnabled() {
		t.Fatal("expected Shadowsocks proxy to be enabled")
	}
}

func TestLoad_EgressShadowsocks_2022Chacha20Accepted(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    shadowsocks:
      uri: "`+ssURI("2022-blake3-chacha20-poly1305", "MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXY=", "127.0.0.1", 8388)+`"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Kernel.Egress.Shadowsocks.Method != "2022-blake3-chacha20-poly1305" {
		t.Fatalf("method: got %q", cfg.Kernel.Egress.Shadowsocks.Method)
	}
	if !cfg.Kernel.Egress.ShadowsocksEnabled() {
		t.Fatal("expected Shadowsocks proxy to be enabled")
	}
}

func TestLoad_Egress_Conflict(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
kernel:
  egress:
    socks5:
      address: "127.0.0.1"
      port: 1080
    shadowsocks:
      uri: "`+ssURI("aes-128-gcm", "test-password", "127.0.0.1", 8388)+`"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for mutually exclusive egress upstreams")
	}
}

func TestLoadRoot_LegacyConfigNormalizesToSingleInstance(t *testing.T) {
	path := writeTemp(t, `
panel:
  url: "https://panel.example.com"
  token: "tok"
  node_id: 1
`)
	root, err := LoadRoot(path)
	if err != nil {
		t.Fatalf("LoadRoot: %v", err)
	}
	instances, err := root.NormalizeInstances()
	if err != nil {
		t.Fatalf("NormalizeInstances: %v", err)
	}
	if len(instances) != 1 {
		t.Fatalf("instances: got %d, want 1", len(instances))
	}
	if instances[0].Panel.URL != "https://panel.example.com" {
		t.Errorf("instance url: got %q", instances[0].Panel.URL)
	}
	if instances[0].InstanceID == "" {
		t.Fatal("expected auto instance id")
	}
}

func TestLoadRoot_InstancesConfig(t *testing.T) {
	path := writeTemp(t, `
instances:
  - panel:
      url: "https://panel-a.example.com"
      token_env: "PANEL_A_TOKEN"
      node_id: 1
    kernel:
      type: singbox
  - panel:
      url: "https://panel-b.example.com"
    machine:
      machine_id: 2
      token_env: "PANEL_B_MACHINE_TOKEN"
    kernel:
      type: singbox
`)
	t.Setenv("PANEL_A_TOKEN", "token-a")
	t.Setenv("PANEL_B_MACHINE_TOKEN", "token-b")
	root, err := LoadRoot(path)
	if err != nil {
		t.Fatalf("LoadRoot: %v", err)
	}
	instances, err := root.NormalizeInstances()
	if err != nil {
		t.Fatalf("NormalizeInstances: %v", err)
	}
	if len(instances) != 2 {
		t.Fatalf("instances: got %d, want 2", len(instances))
	}
	if instances[0].Panel.Token != "token-a" {
		t.Errorf("panel a token: got %q", instances[0].Panel.Token)
	}
	if instances[1].Machine == nil || instances[1].Machine.Token != "token-b" {
		t.Fatalf("machine token: got %+v", instances[1].Machine)
	}
	if instances[0].InstanceID == instances[1].InstanceID {
		t.Fatal("expected unique instance ids")
	}
}

func TestConfig_AutoInstanceIDStable(t *testing.T) {
	cfg := &Config{Panel: PanelConfig{URL: "https://Panel.Example.com/", NodeID: 1, Token: "tok"}}
	cfg.setDefaultsFrom("/etc/mi-node")
	id1, err := cfg.AutoInstanceID()
	if err != nil {
		t.Fatalf("AutoInstanceID: %v", err)
	}
	id2, err := cfg.AutoInstanceID()
	if err != nil {
		t.Fatalf("AutoInstanceID second: %v", err)
	}
	if id1 != id2 {
		t.Fatalf("ids differ: %q vs %q", id1, id2)
	}
}

func TestLoadRoot_InheritanceFromTopLevel(t *testing.T) {
	path := writeTemp(t, `
log:
  level: "debug"
  output: "stderr"
kernel:
  type: xray
  log_level: "error"
node:
  push_interval: 42
  pull_interval: 99
instances:
  - panel:
      url: "https://panel.example.com"
      token: "tok-a"
      node_id: 1
  - panel:
      url: "https://panel.example.com"
      token: "tok-b"
      node_id: 2
    log:
      level: "warn"
`)
	root, err := LoadRoot(path)
	if err != nil {
		t.Fatalf("LoadRoot: %v", err)
	}
	if len(root.Instances) != 2 {
		t.Fatalf("instances: got %d, want 2", len(root.Instances))
	}
	// Instance 0: inherits everything from top-level.
	inst0 := root.Instances[0]
	if inst0.Log.Level != "debug" {
		t.Errorf("inst0 log.level: got %q, want %q", inst0.Log.Level, "debug")
	}
	if inst0.Log.Output != "stderr" {
		t.Errorf("inst0 log.output: got %q, want %q", inst0.Log.Output, "stderr")
	}
	if inst0.Kernel.Type != "xray" {
		t.Errorf("inst0 kernel.type: got %q, want %q", inst0.Kernel.Type, "xray")
	}
	if inst0.Kernel.LogLevel != "error" {
		t.Errorf("inst0 kernel.log_level: got %q, want %q", inst0.Kernel.LogLevel, "error")
	}
	if inst0.Node.PushInterval != 42 {
		t.Errorf("inst0 push_interval: got %d, want 42", inst0.Node.PushInterval)
	}
	if inst0.Node.PullInterval != 99 {
		t.Errorf("inst0 pull_interval: got %d, want 99", inst0.Node.PullInterval)
	}
	// Instance 1: overrides log.level, inherits the rest.
	inst1 := root.Instances[1]
	if inst1.Log.Level != "warn" {
		t.Errorf("inst1 log.level: got %q, want %q", inst1.Log.Level, "warn")
	}
	if inst1.Log.Output != "stderr" {
		t.Errorf("inst1 log.output: got %q, want %q", inst1.Log.Output, "stderr")
	}
	if inst1.Kernel.Type != "xray" {
		t.Errorf("inst1 kernel.type: got %q, want %q", inst1.Kernel.Type, "xray")
	}
}

func TestLoadRoot_InstanceOrderDoesNotAffectConfigDir(t *testing.T) {
	yamlTmpl := func(first, second int) string {
		return fmt.Sprintf(`
instances:
  - panel:
      url: "https://panel.example.com"
      token: "tok-a"
      node_id: %d
  - panel:
      url: "https://panel.example.com"
      token: "tok-b"
      node_id: %d
`, first, second)
	}

	path1 := writeTemp(t, yamlTmpl(1, 2))
	path2 := writeTemp(t, yamlTmpl(2, 1))
	root1, err := LoadRoot(path1)
	if err != nil {
		t.Fatalf("LoadRoot order1: %v", err)
	}
	root2, err := LoadRoot(path2)
	if err != nil {
		t.Fatalf("LoadRoot order2: %v", err)
	}

	// Collect the config_dir suffix (relative to base) by InstanceID.
	suffix := func(instances []Config) map[string]string {
		m := map[string]string{}
		for _, inst := range instances {
			// The config_dir ends with .../{instanceID}, extract last component.
			m[inst.InstanceID] = filepath.Base(inst.Kernel.ConfigDir)
		}
		return m
	}
	dirs1 := suffix(root1.Instances)
	dirs2 := suffix(root2.Instances)

	for id, s1 := range dirs1 {
		s2, ok := dirs2[id]
		if !ok {
			t.Fatalf("instance %q missing in reversed order", id)
		}
		if s1 != s2 {
			t.Errorf("instance %q config_dir suffix differs: %q vs %q", id, s1, s2)
		}
	}
}

func TestInheritFrom_AutoTLSNotForcedWhenChildHasCertMode(t *testing.T) {
	parent := &Config{Cert: CertConfig{AutoTLS: true, Domain: "example.com"}}
	child := &Config{Cert: CertConfig{CertMode: "file", CertFile: "/etc/cert.pem"}}
	child.inheritFrom(parent)
	if child.Cert.AutoTLS {
		t.Error("auto_tls should NOT be inherited when child has explicit cert_mode")
	}
	if child.Cert.Domain != "example.com" {
		t.Errorf("domain: got %q, want %q", child.Cert.Domain, "example.com")
	}
}

func TestInheritFrom_AutoTLSInheritedWhenChildHasNoCertConfig(t *testing.T) {
	parent := &Config{Cert: CertConfig{AutoTLS: true, Domain: "example.com"}}
	child := &Config{}
	child.inheritFrom(parent)
	if !child.Cert.AutoTLS {
		t.Error("auto_tls should be inherited when child has no cert config")
	}
}
