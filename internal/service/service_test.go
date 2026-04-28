package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/micah123321/mi-node/internal/cert"
	"github.com/micah123321/mi-node/internal/config"
	"github.com/micah123321/mi-node/internal/limiter"
	"github.com/micah123321/mi-node/internal/model"
	"github.com/micah123321/mi-node/internal/trafficlimit"
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

func TestApplyUserUpdateCachesUsersWhenTrafficLimitSuspended(t *testing.T) {
	now := time.Date(2026, 4, 28, 12, 0, 0, 0, time.UTC)
	manager := trafficlimit.New("", func() time.Time { return now })
	if action, err := manager.Configure(trafficlimit.Config{
		Enabled:     true,
		Limit:       100,
		CurrentUsed: 100,
		ResetDay:    1,
		ResetTime:   "00:00",
		Timezone:    "UTC",
	}); err != nil || action != trafficlimit.ActionSuspend {
		t.Fatalf("Configure() action = %v error = %v, want suspend without error", action, err)
	}

	l := limiter.New()
	fakeKernel := &fakeDebugKernel{}
	svc := &Service{
		kernel:       fakeKernel,
		trafficLimit: manager,
		limiter:      l,
		speedTracker: limiter.NewSpeedTracker(l),
		lastConfig:   &model.NodeSpec{Protocol: "shadowsocks", ServerPort: 12345},
		lastUsers:    []model.UserSpec{{ID: 1, UUID: "old"}},
	}

	svc.applyUserUpdate(context.Background(), []model.UserSpec{{ID: 2, UUID: "new"}}, "hash-from-panel")

	if fakeKernel.startCalls != 0 || fakeKernel.updateCalls != 0 {
		t.Fatalf("kernel calls while suspended: start=%d update=%d, want 0", fakeKernel.startCalls, fakeKernel.updateCalls)
	}
	if len(svc.lastUsers) != 1 || svc.lastUsers[0].ID != 2 || svc.lastUsers[0].UUID != "new" {
		t.Fatalf("lastUsers = %+v, want updated suspended cache", svc.lastUsers)
	}
	if svc.lastUserHash != "hash-from-panel" {
		t.Fatalf("lastUserHash = %q, want panel hash", svc.lastUserHash)
	}
}

func TestApplyUserDeltaCachesUsersWhenTrafficLimitSuspended(t *testing.T) {
	now := time.Date(2026, 4, 28, 12, 0, 0, 0, time.UTC)
	manager := trafficlimit.New("", func() time.Time { return now })
	if action, err := manager.Configure(trafficlimit.Config{
		Enabled:     true,
		Limit:       100,
		CurrentUsed: 100,
		ResetDay:    1,
		ResetTime:   "00:00",
		Timezone:    "UTC",
	}); err != nil || action != trafficlimit.ActionSuspend {
		t.Fatalf("Configure() action = %v error = %v, want suspend without error", action, err)
	}

	l := limiter.New()
	fakeKernel := &fakeDebugKernel{}
	svc := &Service{
		kernel:       fakeKernel,
		trafficLimit: manager,
		limiter:      l,
		speedTracker: limiter.NewSpeedTracker(l),
		lastConfig:   &model.NodeSpec{Protocol: "shadowsocks", ServerPort: 12345},
		lastUsers:    []model.UserSpec{{ID: 1, UUID: "one"}},
	}

	svc.applyUserDelta(context.Background(), "add", []model.UserSpec{{ID: 2, UUID: "two"}})
	if fakeKernel.startCalls != 0 || fakeKernel.addCalls != 0 {
		t.Fatalf("kernel add calls while suspended: start=%d add=%d, want 0", fakeKernel.startCalls, fakeKernel.addCalls)
	}
	if len(svc.lastUsers) != 2 {
		t.Fatalf("lastUsers after add = %+v, want 2 users", svc.lastUsers)
	}

	svc.applyUserDelta(context.Background(), "remove", []model.UserSpec{{ID: 1}})
	if fakeKernel.removeCalls != 0 {
		t.Fatalf("kernel remove calls while suspended = %d, want 0", fakeKernel.removeCalls)
	}
	if len(svc.lastUsers) != 1 || svc.lastUsers[0].ID != 2 {
		t.Fatalf("lastUsers after remove = %+v, want only user 2", svc.lastUsers)
	}
}
