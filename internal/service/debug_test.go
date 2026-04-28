package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/micah123321/mi-node/internal/config"
	"github.com/micah123321/mi-node/internal/kernel"
	"github.com/micah123321/mi-node/internal/model"
	"golang.org/x/time/rate"
)

type fakeDebugKernel struct {
	name        string
	running     bool
	defaultTag  string
	probeDelay  time.Duration
	probeErr    error
	probeCalls  int
	startCalls  int
	updateCalls int
	addCalls    int
	removeCalls int
}

func (f *fakeDebugKernel) Name() string { return f.name }

func (f *fakeDebugKernel) Protocols() []string { return nil }

func (f *fakeDebugKernel) Capabilities() kernel.Capabilities { return kernel.Capabilities{} }

func (f *fakeDebugKernel) Start(*model.NodeSpec, []model.UserSpec, kernel.TLSCert) error {
	f.startCalls++
	f.running = true
	return nil
}

func (f *fakeDebugKernel) Stop() { f.running = false }

func (f *fakeDebugKernel) IsRunning() bool { return f.running }

func (f *fakeDebugKernel) Reload(*model.NodeSpec, []model.UserSpec, kernel.TLSCert) error { return nil }

func (f *fakeDebugKernel) AddUsers(users []model.UserSpec) (int, error) {
	f.addCalls++
	return len(users), nil
}

func (f *fakeDebugKernel) RemoveUsers(users []model.UserSpec) (int, error) {
	f.removeCalls++
	return len(users), nil
}

func (f *fakeDebugKernel) UpdateUsers(users []model.UserSpec) (int, int, error) {
	f.updateCalls++
	return len(users), 0, nil
}

func (f *fakeDebugKernel) GetUserTraffic(context.Context) (map[int][2]int64, map[int]map[string]bool, int, error) {
	return nil, nil, 0, nil
}

func (f *fakeDebugKernel) CloseConnection(context.Context, string) error { return nil }

func (f *fakeDebugKernel) CloseUserConnections(context.Context, string) error { return nil }

func (f *fakeDebugKernel) SetSpeedLimitFunc(func(string) *rate.Limiter) {}

func (f *fakeDebugKernel) SetDeviceLimitFunc(func(string) (int, bool)) {}

func (f *fakeDebugKernel) UpdateGlobalDevices(map[int][]string) {}

func (f *fakeDebugKernel) ClearGlobalDevices() {}

func (f *fakeDebugKernel) CurrentDefaultOutboundTag() string { return f.defaultTag }

func (f *fakeDebugKernel) DefaultOutboundProbe(context.Context, string, string) (time.Duration, error) {
	f.probeCalls++
	if f.probeErr != nil {
		return f.probeDelay, f.probeErr
	}
	return f.probeDelay, nil
}

func testDebugConfig() *config.Config {
	return &config.Config{
		Panel: config.PanelConfig{
			NodeID: 322,
		},
		Kernel: config.KernelConfig{
			Type: "singbox",
			Egress: config.EgressConfig{
				Shadowsocks: config.ShadowsocksEgressConfig{
					Address:  "38.182.122.32",
					Port:     30333,
					Method:   "2022-blake3-aes-256-gcm",
					Password: "hidden",
				},
			},
		},
	}
}

func TestDebugEgressStatus_PendingProbe(t *testing.T) {
	svc := &Service{
		cfg: testDebugConfig(),
		kernel: &fakeDebugKernel{
			name:       "sing-box",
			running:    false,
			defaultTag: config.DefaultShadowsocksProxyTag,
		},
	}

	status := svc.DebugEgressStatus()
	if !status.ProbeEnabled {
		t.Fatal("expected probe to be enabled for sing-box + shadowsocks egress")
	}
	if status.DefaultOutboundTag != config.DefaultShadowsocksProxyTag {
		t.Fatalf("default_outbound_tag = %q, want %q", status.DefaultOutboundTag, config.DefaultShadowsocksProxyTag)
	}
	if status.ShadowsocksUpstream == nil {
		t.Fatal("expected shadowsocks upstream to be present")
	}
	if status.ShadowsocksUpstream.Address != "38.182.122.32" {
		t.Fatalf("upstream address = %q", status.ShadowsocksUpstream.Address)
	}
	if status.LastProbe.Error != "kernel not running" {
		t.Fatalf("last_probe.error = %q, want %q", status.LastProbe.Error, "kernel not running")
	}
}

func TestTriggerShadowsocksEgressProbe_StoresLatestResult(t *testing.T) {
	fakeKernel := &fakeDebugKernel{
		name:       "sing-box",
		running:    true,
		defaultTag: config.DefaultShadowsocksProxyTag,
		probeDelay: 25 * time.Millisecond,
	}
	svc := &Service{
		cfg:    testDebugConfig(),
		kernel: fakeKernel,
	}

	svc.triggerShadowsocksEgressProbe("test")

	deadline := time.Now().Add(2 * time.Second)
	for {
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for egress probe result")
		}
		result := svc.lastEgressProbeSnapshot()
		if result.CheckedAt != "" {
			if !result.Success {
				t.Fatalf("expected successful probe, got error %q", result.Error)
			}
			if result.Target != defaultEgressProbeTarget {
				t.Fatalf("target = %q, want %q", result.Target, defaultEgressProbeTarget)
			}
			if result.Network != defaultEgressProbeNetwork {
				t.Fatalf("network = %q, want %q", result.Network, defaultEgressProbeNetwork)
			}
			if fakeKernel.probeCalls != 1 {
				t.Fatalf("probeCalls = %d, want 1", fakeKernel.probeCalls)
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestDebugEgressStatus_UnsupportedKernel(t *testing.T) {
	cfg := testDebugConfig()
	cfg.Kernel.Type = "xray"

	svc := &Service{
		cfg: cfg,
		kernel: &fakeDebugKernel{
			name:       "xray",
			running:    true,
			defaultTag: config.DefaultShadowsocksProxyTag,
			probeErr:   errors.New("unreachable"),
		},
	}

	status := svc.DebugEgressStatus()
	if status.ProbeEnabled {
		t.Fatal("expected probe to be disabled outside sing-box")
	}
	if status.LastProbe.Error != "egress debug probe is only available for sing-box" {
		t.Fatalf("last_probe.error = %q", status.LastProbe.Error)
	}
}
