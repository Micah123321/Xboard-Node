package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/micah123321/mi-node/internal/cert"
	"github.com/micah123321/mi-node/internal/config"
	"github.com/micah123321/mi-node/internal/model"
)

func TestEnsureTLSCertificateAutoSelfSigned(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := &config.Config{
		Cert: config.CertConfig{
			CertMode: "none",
			CertDir:  tmpDir,
		},
	}

	svc := &Service{
		cfg:  cfg,
		cert: cert.NewManager(cfg.Cert),
	}
	nc := &model.NodeSpec{
		Protocol:   "tuic",
		ServerName: "node.example.com",
	}

	if err := svc.ensureTLSCertificate(context.Background(), nc); err != nil {
		t.Fatalf("ensureTLSCertificate: %v", err)
	}

	if svc.cfg.Cert.CertMode != "self" {
		t.Fatalf("cert mode: got %q, want %q", svc.cfg.Cert.CertMode, "self")
	}
	if svc.cfg.Cert.Domain != "node.example.com" {
		t.Fatalf("cert domain: got %q, want %q", svc.cfg.Cert.Domain, "node.example.com")
	}
	if !certFilesAvailable(svc.cert.CertFile(), svc.cert.KeyFile()) {
		t.Fatalf("expected generated cert files, got cert=%q key=%q", svc.cert.CertFile(), svc.cert.KeyFile())
	}
}

func TestEnsureTLSCertificateSkipsPlainProtocols(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := &config.Config{
		Cert: config.CertConfig{
			CertMode: "none",
			CertDir:  tmpDir,
		},
	}

	svc := &Service{
		cfg:  cfg,
		cert: cert.NewManager(cfg.Cert),
	}
	nc := &model.NodeSpec{
		Protocol: "shadowsocks",
	}

	if err := svc.ensureTLSCertificate(context.Background(), nc); err != nil {
		t.Fatalf("ensureTLSCertificate: %v", err)
	}
	if svc.cfg.Cert.CertMode != "none" {
		t.Fatalf("cert mode should stay none, got %q", svc.cfg.Cert.CertMode)
	}
	if svc.cert.CertFile() != "" || svc.cert.KeyFile() != "" {
		t.Fatalf("plain protocol should not create cert files, got cert=%q key=%q", svc.cert.CertFile(), svc.cert.KeyFile())
	}
}

func TestInferCertificateDomain(t *testing.T) {
	nc := &model.NodeSpec{
		Host: "edge.example.com:443",
		TLSSettings: map[string]interface{}{
			"server_name": "tls.example.com",
		},
	}
	if got := inferCertificateDomain(nc); got != "edge.example.com" {
		t.Fatalf("inferCertificateDomain: got %q, want %q", got, "edge.example.com")
	}
}

func TestCertFilesAvailable(t *testing.T) {
	tmpDir := t.TempDir()
	certPath := filepath.Join(tmpDir, "cert.pem")
	keyPath := filepath.Join(tmpDir, "key.pem")

	if certFilesAvailable(certPath, keyPath) {
		t.Fatal("expected false when files are missing")
	}

	if err := os.WriteFile(certPath, []byte("cert"), 0o644); err != nil {
		t.Fatalf("write cert: %v", err)
	}
	if err := os.WriteFile(keyPath, []byte("key"), 0o600); err != nil {
		t.Fatalf("write key: %v", err)
	}

	if !certFilesAvailable(certPath, keyPath) {
		t.Fatal("expected true when both files exist")
	}
}
