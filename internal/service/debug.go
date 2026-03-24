package service

import (
	"context"
	"log/slog"
	"time"
)

const (
	defaultEgressProbeNetwork = "tcp"
	defaultEgressProbeTarget  = "1.1.1.1:443"
	defaultEgressProbeTimeout = 5 * time.Second
)

// EgressDebugStatus is the public shape returned by the local debug endpoint.
type EgressDebugStatus struct {
	NodeID              int                   `json:"node_id"`
	Kernel              string                `json:"kernel"`
	ProbeEnabled        bool                  `json:"probe_enabled"`
	DefaultOutboundTag  string                `json:"default_outbound_tag"`
	ShadowsocksUpstream *ShadowsocksUpstream  `json:"shadowsocks_upstream,omitempty"`
	LastProbe           EgressDialCheckResult `json:"last_probe"`
}

// ShadowsocksUpstream describes the configured default SS upstream without
// exposing secrets.
type ShadowsocksUpstream struct {
	Address string `json:"address"`
	Port    int    `json:"port"`
	Method  string `json:"method"`
}

// EgressDialCheckResult stores the latest real dial outcome through the
// runtime default outbound.
type EgressDialCheckResult struct {
	Network   string `json:"network"`
	Target    string `json:"target"`
	Success   bool   `json:"success"`
	Error     string `json:"error,omitempty"`
	CheckedAt string `json:"checked_at,omitempty"`
	LatencyMS int64  `json:"latency_ms,omitempty"`
}

type egressDebugKernel interface {
	CurrentDefaultOutboundTag() string
	DefaultOutboundProbe(ctx context.Context, network, target string) (time.Duration, error)
}

// DebugEgressStatus returns a snapshot safe for JSON output.
func (s *Service) DebugEgressStatus() EgressDebugStatus {
	status := EgressDebugStatus{
		NodeID:             s.cfg.Panel.NodeID,
		Kernel:             s.kernel.Name(),
		ProbeEnabled:       s.egressProbeEnabled(),
		DefaultOutboundTag: s.cfg.Kernel.Egress.DefaultOutboundTag(),
		LastProbe:          s.defaultEgressProbeStatus(),
	}

	if upstream := s.shadowsocksUpstream(); upstream != nil {
		status.ShadowsocksUpstream = upstream
	}
	if runtimeTag := s.currentDefaultOutboundTag(); runtimeTag != "" {
		status.DefaultOutboundTag = runtimeTag
	}
	if last := s.lastEgressProbeSnapshot(); last.Target != "" {
		status.LastProbe = last
	}

	return status
}

func (s *Service) egressProbeEnabled() bool {
	if s.cfg.Kernel.Type != "singbox" || !s.cfg.Kernel.Egress.ShadowsocksEnabled() {
		return false
	}
	_, ok := s.kernel.(egressDebugKernel)
	return ok
}

func (s *Service) currentDefaultOutboundTag() string {
	debugKernel, ok := s.kernel.(egressDebugKernel)
	if !ok {
		return ""
	}
	return debugKernel.CurrentDefaultOutboundTag()
}

func (s *Service) shadowsocksUpstream() *ShadowsocksUpstream {
	if !s.cfg.Kernel.Egress.ShadowsocksEnabled() {
		return nil
	}
	return &ShadowsocksUpstream{
		Address: s.cfg.Kernel.Egress.Shadowsocks.Address,
		Port:    s.cfg.Kernel.Egress.Shadowsocks.Port,
		Method:  s.cfg.Kernel.Egress.Shadowsocks.Method,
	}
}

func (s *Service) defaultEgressProbeStatus() EgressDialCheckResult {
	status := EgressDialCheckResult{
		Network: defaultEgressProbeNetwork,
		Target:  defaultEgressProbeTarget,
	}

	switch {
	case !s.cfg.Kernel.Egress.ShadowsocksEnabled():
		status.Error = "shadowsocks egress not enabled"
	case !s.egressProbeEnabled():
		status.Error = "egress debug probe is only available for sing-box"
	case !s.kernel.IsRunning():
		status.Error = "kernel not running"
	default:
		status.Error = "probe not run yet"
	}

	return status
}

func (s *Service) lastEgressProbeSnapshot() EgressDialCheckResult {
	s.egressProbeMu.RLock()
	defer s.egressProbeMu.RUnlock()
	return s.lastEgressProbe
}

func (s *Service) setLastEgressProbe(result EgressDialCheckResult) {
	s.egressProbeMu.Lock()
	defer s.egressProbeMu.Unlock()
	s.lastEgressProbe = result
}

func (s *Service) logShadowsocksEgressStatus(phase string) {
	status := s.DebugEgressStatus()
	if status.ShadowsocksUpstream == nil {
		return
	}

	slog.Info("shadowsocks egress active",
		"phase", phase,
		"node_id", status.NodeID,
		"default_outbound_tag", status.DefaultOutboundTag,
		"address", status.ShadowsocksUpstream.Address,
		"port", status.ShadowsocksUpstream.Port,
		"method", status.ShadowsocksUpstream.Method,
		"probe_enabled", status.ProbeEnabled,
	)
}

func (s *Service) triggerShadowsocksEgressProbe(reason string) {
	if !s.egressProbeEnabled() || !s.kernel.IsRunning() {
		return
	}

	debugKernel := s.kernel.(egressDebugKernel)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), defaultEgressProbeTimeout)
		defer cancel()

		latency, err := debugKernel.DefaultOutboundProbe(ctx, defaultEgressProbeNetwork, defaultEgressProbeTarget)
		result := EgressDialCheckResult{
			Network:   defaultEgressProbeNetwork,
			Target:    defaultEgressProbeTarget,
			Success:   err == nil,
			CheckedAt: time.Now().Format(time.RFC3339),
			LatencyMS: latency.Milliseconds(),
		}
		if err != nil {
			result.Error = err.Error()
		}

		s.setLastEgressProbe(result)

		status := s.DebugEgressStatus()
		if err != nil {
			slog.Warn("shadowsocks egress probe failed",
				"reason", reason,
				"node_id", status.NodeID,
				"default_outbound_tag", status.DefaultOutboundTag,
				"target", result.Target,
				"latency_ms", result.LatencyMS,
				"error", result.Error,
			)
			return
		}

		slog.Info("shadowsocks egress probe succeeded",
			"reason", reason,
			"node_id", status.NodeID,
			"default_outbound_tag", status.DefaultOutboundTag,
			"target", result.Target,
			"latency_ms", result.LatencyMS,
		)
	}()
}
