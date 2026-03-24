package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/cedar2025/xboard-node/internal/service"
)

func TestNewDebugMux_ReturnsStatuses(t *testing.T) {
	mux := newDebugMux(func() []service.EgressDebugStatus {
		return []service.EgressDebugStatus{
			{
				NodeID:             322,
				Kernel:             "sing-box",
				ProbeEnabled:       true,
				DefaultOutboundTag: "default-shadowsocks",
				ShadowsocksUpstream: &service.ShadowsocksUpstream{
					Address: "38.182.122.32",
					Port:    30333,
					Method:  "2022-blake3-aes-256-gcm",
				},
				LastProbe: service.EgressDialCheckResult{
					Network:   "tcp",
					Target:    "1.1.1.1:443",
					Success:   true,
					CheckedAt: "2026-03-25T06:20:00+08:00",
					LatencyMS: 42,
				},
			},
		}
	})

	req := httptest.NewRequest(http.MethodGet, "/debug/egress", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want %q", got, "no-store")
	}

	var resp struct {
		Nodes []service.EgressDebugStatus `json:"nodes"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if len(resp.Nodes) != 1 {
		t.Fatalf("nodes len = %d, want 1", len(resp.Nodes))
	}
	if resp.Nodes[0].DefaultOutboundTag != "default-shadowsocks" {
		t.Fatalf("default_outbound_tag = %q", resp.Nodes[0].DefaultOutboundTag)
	}
	if resp.Nodes[0].ShadowsocksUpstream == nil {
		t.Fatal("expected shadowsocks_upstream")
	}
}

func TestNewDebugMux_MethodNotAllowed(t *testing.T) {
	mux := newDebugMux(func() []service.EgressDebugStatus { return nil })

	req := httptest.NewRequest(http.MethodPost, "/debug/egress", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
	if got := rec.Header().Get("Allow"); got != http.MethodGet {
		t.Fatalf("Allow = %q, want %q", got, http.MethodGet)
	}
}
