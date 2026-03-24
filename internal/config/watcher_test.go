package config

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestWatchConfigReloadsValidConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yml")
	if err := os.WriteFile(path, []byte(`
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
log:
  level: "info"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	got := make(chan *Config, 1)
	watcher, err := WatchConfig(ctx, path, func(cfg *Config) {
		got <- cfg
	})
	if err != nil {
		t.Fatalf("WatchConfig: %v", err)
	}
	defer watcher.Stop()
	watcher.debounce = 20 * time.Millisecond

	if err := os.WriteFile(path, []byte(`
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
log:
  level: "debug"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	select {
	case cfg := <-got:
		if cfg.Log.Level != "debug" {
			t.Fatalf("got log.level %q, want debug", cfg.Log.Level)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for config reload")
	}
}

func TestWatchConfigIgnoresInvalidConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yml")
	if err := os.WriteFile(path, []byte(`
panel:
  url: "https://example.com"
  token: "tok"
  node_id: 1
`), 0o644); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	got := make(chan *Config, 1)
	watcher, err := WatchConfig(ctx, path, func(cfg *Config) {
		got <- cfg
	})
	if err != nil {
		t.Fatalf("WatchConfig: %v", err)
	}
	defer watcher.Stop()
	watcher.debounce = 20 * time.Millisecond

	if err := os.WriteFile(path, []byte(`
panel:
  url: "https://example.com"
  node_id: 1
`), 0o644); err != nil {
		t.Fatal(err)
	}

	select {
	case cfg := <-got:
		t.Fatalf("unexpected reload callback for invalid config: %+v", cfg)
	case <-time.After(500 * time.Millisecond):
	}
}
