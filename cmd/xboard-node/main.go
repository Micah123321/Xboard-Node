package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/cedar2025/xboard-node/internal/config"
	"github.com/cedar2025/xboard-node/internal/service"
)

var (
	version   = "dev"
	buildTime = "unknown"
)

type serviceRegistry struct {
	mu       sync.RWMutex
	services []*service.Service
}

func (r *serviceRegistry) Set(services []*service.Service) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.services = append([]*service.Service(nil), services...)
}

func (r *serviceRegistry) SnapshotDebugStatuses() []service.EgressDebugStatus {
	r.mu.RLock()
	services := append([]*service.Service(nil), r.services...)
	r.mu.RUnlock()

	statuses := make([]service.EgressDebugStatus, 0, len(services))
	for _, svc := range services {
		if svc == nil {
			continue
		}
		statuses = append(statuses, svc.DebugEgressStatus())
	}
	return statuses
}

func newHealthMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	return mux
}

func newDebugMux(statuses func() []service.EgressDebugStatus) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/debug/egress", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Content-Type-Options", "nosniff")

		resp := struct {
			Nodes []service.EgressDebugStatus `json:"nodes"`
		}{
			Nodes: statuses(),
		}

		if err := json.NewEncoder(w).Encode(resp); err != nil {
			slog.Warn("failed to write debug response", "error", err)
		}
	})
	return mux
}

func main() {
	configPath := flag.String("c", "config.yml", "config file path")
	showVersion := flag.Bool("v", false, "show version")
	flag.Parse()

	if *showVersion {
		fmt.Printf("xboard-node %s (built %s)\n", version, buildTime)
		os.Exit(0)
	}

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	config.InitLogger(cfg.Log)

	// Apply runtime memory tuning before anything else allocates.
	applyRuntimeConfig(cfg.Runtime)

	runWithReload(cfg, *configPath)
}

func runWithReload(initialCfg *config.Config, configPath string) {
	var healthSrv *http.Server
	var healthPort int
	var debugSrv *http.Server
	var debugPort int
	var registry serviceRegistry

	startHealth := func(port int) {
		if port <= 0 {
			healthPort = 0
			return
		}
		ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err != nil {
			slog.Error("failed to start health check listener", "port", port, "error", err)
			os.Exit(1)
		}
		healthSrv = &http.Server{Handler: newHealthMux(), ReadHeaderTimeout: 5 * time.Second}
		healthPort = port
		go func() {
			slog.Info("health check listening", "addr", ln.Addr())
			if err := healthSrv.Serve(ln); err != nil && err != http.ErrServerClosed {
				slog.Warn("health check server stopped", "error", err)
			}
		}()
	}

	startDebug := func(port int) {
		if port <= 0 {
			debugPort = 0
			return
		}
		ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err != nil {
			slog.Error("failed to start local debug listener", "port", port, "error", err)
			os.Exit(1)
		}
		debugSrv = &http.Server{Handler: newDebugMux(registry.SnapshotDebugStatuses), ReadHeaderTimeout: 5 * time.Second}
		debugPort = port
		go func() {
			slog.Info("local debug listening", "addr", ln.Addr())
			if err := debugSrv.Serve(ln); err != nil && err != http.ErrServerClosed {
				slog.Warn("local debug server stopped", "error", err)
			}
		}()
	}

	closeHealth := func() {
		if healthSrv != nil {
			_ = healthSrv.Close()
			healthSrv = nil
		}
		healthPort = 0
	}

	closeDebug := func() {
		if debugSrv != nil {
			_ = debugSrv.Close()
			debugSrv = nil
		}
		debugPort = 0
	}

	defer closeHealth()
	defer closeDebug()

	for cfg := initialCfg; ; {
		if cfg.HealthPort != healthPort {
			closeHealth()
			startHealth(cfg.HealthPort)
		}
		if cfg.DebugPort != debugPort {
			closeDebug()
			startDebug(cfg.DebugPort)
		}

		nodes := cfg.ExpandNodes()
		slog.Info("xboard-node starting",
			"version", version,
			"build_time", buildTime,
			"nodes", len(nodes),
		)

		ctx, cancel := context.WithCancel(context.Background())
		reloadCh := make(chan *config.Config, 1)

		watcher, err := config.WatchConfig(ctx, configPath, func(newCfg *config.Config) {
			select {
			case reloadCh <- newCfg:
			default:
			}
		})
		if err != nil {
			slog.Warn("config watcher unavailable, hot-reload disabled", "error", err)
		}

		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

		go func() {
			select {
			case sig := <-sigCh:
				slog.Info("received signal, shutting down gracefully", "signal", sig)
				cancel()

				select {
				case sig = <-sigCh:
					slog.Warn("received second signal, forcing exit", "signal", sig)
					os.Exit(1)
				case <-time.After(15 * time.Second):
					slog.Error("shutdown timed out after 15s, forcing exit")
					os.Exit(2)
				}
			case <-ctx.Done():
			}
		}()

		errCh := make(chan error, len(nodes))
		var wg sync.WaitGroup
		services := make([]*service.Service, 0, len(nodes))
		for _, nodeCfg := range nodes {
			nodeCfg := nodeCfg
			svc := service.New(nodeCfg)
			services = append(services, svc)
			wg.Add(1)
			go func(svc *service.Service) {
				defer wg.Done()
				if err := svc.Run(ctx); err != nil {
					slog.Error("node service exited with error",
						"node_id", nodeCfg.Panel.NodeID, "error", err)
					errCh <- err
					cancel()
				} else {
					slog.Info("node service stopped", "node_id", nodeCfg.Panel.NodeID)
				}
			}(svc)
		}
		registry.Set(services)

		doneCh := make(chan struct{})
		go func() {
			wg.Wait()
			close(doneCh)
		}()

		var newCfg *config.Config
		select {
		case newCfg = <-reloadCh:
			slog.Info("config changed, restarting services")
			cancel()
			<-doneCh
		case <-doneCh:
		}

		signal.Stop(sigCh)
		if watcher != nil {
			watcher.Stop()
		}
		cancel()

		if newCfg == nil {
			close(errCh)
			if err := firstError(errCh); err != nil {
				os.Exit(1)
			}
			slog.Info("xboard-node stopped")
			return
		}

		config.InitLogger(newCfg.Log)
		applyRuntimeConfig(newCfg.Runtime)
		cfg = newCfg
		slog.Info("reload complete, services restarting with new config")
	}
}

func firstError(errCh <-chan error) error {
	for err := range errCh {
		if err != nil {
			return err
		}
	}
	return nil
}

// applyRuntimeConfig wires up Go runtime memory limits from the config file.
// Both settings can also be overridden by environment variables (GOMEMLIMIT /
// GOGC) — the env vars take precedence because Go's runtime reads them before
// we can call these functions, but we set them here for completeness and so
// the values are logged.
func applyRuntimeConfig(rt config.RuntimeConfig) {
	// GOGC
	if rt.GoGCPercent > 0 {
		prev := debug.SetGCPercent(rt.GoGCPercent)
		slog.Info("runtime: GOGC set", "gogc", rt.GoGCPercent, "prev", prev)
	}

	// GOMEMLIMIT — parse human-readable size string (e.g. "30MiB")
	if rt.GoMemLimit != "" {
		limit, err := parseMemLimit(rt.GoMemLimit)
		if err != nil {
			slog.Warn("runtime: invalid gomemlimit, ignoring", "value", rt.GoMemLimit, "error", err)
		} else {
			prev := debug.SetMemoryLimit(limit)
			slog.Info("runtime: GOMEMLIMIT set",
				"limit", rt.GoMemLimit,
				"bytes", limit,
				"prev_bytes", prev,
			)
		}
	}
}

// parseMemLimit converts a human-readable size string to bytes.
// Supported suffixes: B, KiB, MiB, GiB, TiB (case-insensitive).
func parseMemLimit(s string) (int64, error) {
	s = strings.TrimSpace(s)
	suffixes := []struct {
		suffix string
		mult   int64
	}{
		{"TiB", 1 << 40},
		{"GiB", 1 << 30},
		{"MiB", 1 << 20},
		{"KiB", 1 << 10},
		{"B", 1},
	}
	upper := strings.ToUpper(s)
	for _, sf := range suffixes {
		if strings.HasSuffix(upper, strings.ToUpper(sf.suffix)) {
			numStr := strings.TrimSuffix(upper, strings.ToUpper(sf.suffix))
			numStr = strings.TrimSpace(numStr)
			var n int64
			if _, err := fmt.Sscanf(numStr, "%d", &n); err != nil {
				return 0, fmt.Errorf("parse number %q: %w", numStr, err)
			}
			return n * sf.mult, nil
		}
	}
	// No suffix: treat as raw bytes.
	var n int64
	if _, err := fmt.Sscanf(s, "%d", &n); err != nil {
		return 0, fmt.Errorf("unrecognised size format %q", s)
	}
	return n, nil
}
