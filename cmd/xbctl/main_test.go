package main

import (
	"os"
	"strings"
	"testing"

	"github.com/micah123321/mi-node/internal/config"
)

func TestWriteRootConfigPreservesInstanceEgress(t *testing.T) {
	t.Setenv("MI_NODE_API_TOKEN", "token")
	path := t.TempDir() + "/config.yml"

	root := &config.RootConfig{
		Instances: []config.Config{
			{
				Panel: config.PanelConfig{
					URL:      "https://panel.example.com",
					TokenEnv: "MI_NODE_API_TOKEN",
					NodeID:   1,
				},
				Kernel: config.KernelConfig{
					Type:      "singbox",
					ConfigDir: "/etc/mi-node",
					Egress: config.EgressConfig{
						SOCKS5: config.SOCKS5EgressConfig{
							Address: "127.0.0.1",
							Port:    1080,
						},
					},
				},
				Log: config.LogConfig{Level: "info", Output: "stdout"},
			},
		},
	}

	if err := writeRootConfig(path, root); err != nil {
		t.Fatalf("writeRootConfig: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(data), "egress:") {
		t.Fatalf("written config does not contain egress:\n%s", data)
	}

	loaded, err := config.LoadRoot(path)
	if err != nil {
		t.Fatalf("LoadRoot: %v", err)
	}
	instances, err := loaded.NormalizeInstances()
	if err != nil {
		t.Fatalf("NormalizeInstances: %v", err)
	}
	if got := instances[0].Kernel.Egress.SOCKS5.Address; got != "127.0.0.1" {
		t.Fatalf("SOCKS5 address = %q, want 127.0.0.1", got)
	}
	if got := instances[0].Kernel.Egress.SOCKS5.Port; got != 1080 {
		t.Fatalf("SOCKS5 port = %d, want 1080", got)
	}
}
