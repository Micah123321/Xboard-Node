package singbox

import (
	"context"
	"fmt"
	"time"

	"github.com/sagernet/sing-box/adapter"
	metadata "github.com/sagernet/sing/common/metadata"
	singService "github.com/sagernet/sing/service"
)

// CurrentDefaultOutboundTag returns the runtime default outbound tag when the
// embedded sing-box instance is running.
func (s *SingBox) CurrentDefaultOutboundTag() string {
	outbound, err := s.defaultOutbound()
	if err != nil {
		return ""
	}
	return outbound.Tag()
}

// DefaultOutboundProbe opens a real outbound connection through the current
// runtime default outbound. This is used by the local debug endpoint to verify
// whether default egress is actually leaving through the configured upstream.
func (s *SingBox) DefaultOutboundProbe(ctx context.Context, network, target string) (time.Duration, error) {
	outbound, err := s.defaultOutbound()
	if err != nil {
		return 0, err
	}

	startedAt := time.Now()
	conn, err := outbound.DialContext(ctx, network, metadata.ParseSocksaddr(target))
	if err != nil {
		return time.Since(startedAt), err
	}
	_ = conn.Close()
	return time.Since(startedAt), nil
}

func (s *SingBox) defaultOutbound() (adapter.Outbound, error) {
	s.mu.Lock()
	ctx := s.ctx
	running := s.box != nil
	s.mu.Unlock()

	if !running || ctx == nil {
		return nil, fmt.Errorf("sing-box not running")
	}

	manager := singService.FromContext[adapter.OutboundManager](ctx)
	if manager == nil {
		return nil, fmt.Errorf("default outbound manager not available")
	}

	outbound := manager.Default()
	if outbound == nil {
		return nil, fmt.Errorf("default outbound not available")
	}

	return outbound, nil
}
