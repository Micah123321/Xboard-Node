package config

import (
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
	if cfg.Kernel.ConfigDir != "/etc/xboard-node" {
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
	expectedCertDir := filepath.Join("/etc/xboard-node", "certs")
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
      address: "127.0.0.1"
      port: 8388
      method: "aes-128-gcm"
      password: "test-password"
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
      address: "cu1.utieol.com"
      port: 50552
      method: "2022-blake3-aes-256-gcm"
      password: "ZWNhZDc0OGIyMmRmYjlmNjliMzM1OTFmMDUwMmY5ZWU=:MDJiODI4NjctYTcwNS00ZTZkLWFjNzEtMDQ1ZjU0ZDY="
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Kernel.Egress.ShadowsocksEnabled() {
		t.Fatal("expected Shadowsocks proxy to be enabled")
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

func TestLoad_EgressShadowsocks_MissingMethod(t *testing.T) {
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
      password: "test-password"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for shadowsocks config without method")
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
      address: "127.0.0.1"
      port: 8388
      method: "2022-blake3-aes-128-gcm"
      password: "not-base64"
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
      address: "127.0.0.1"
      port: 8388
      method: "aes-129-gcm"
      password: "test-password"
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
      address: "127.0.0.1"
      port: 8388
      method: "aes-192-gcm"
      password: "test-password"
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
      address: "127.0.0.1"
      port: 8388
      method: "aes-192-gcm"
      password: "test-password"
`)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
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
      address: "127.0.0.1"
      port: 8388
      method: "aes-128-gcm"
      password: "test-password"
`)
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for mutually exclusive egress upstreams")
	}
}
