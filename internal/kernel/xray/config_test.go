package xray

import (
	"encoding/json"
	"testing"

	"github.com/cedar2025/xboard-node/internal/config"
	"github.com/cedar2025/xboard-node/internal/panel"
)

var testKernelCfg = config.KernelConfig{
	Type:     "xray",
	LogLevel: "warn",
}

var testUsers = []panel.User{
	{ID: 1, UUID: "279d4f89-3a2c-488d-a67c-2d39a72acdde"},
	{ID: 5, UUID: "4d5965c8-a60c-452a-a943-af83ec0bb0db"},
}

func TestBuildConfig_OutboundPriority(t *testing.T) {
	kcfg := config.KernelConfig{
		LogLevel: "info",
		CustomOutbound: []map[string]any{
			{"tag": "block", "protocol": "dns"}, // Local static override
		},
	}
	nc := &panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 111,
		Cipher:     "aes-128-gcm",
		CustomOutbounds: []panel.OutboundConfig{
			{Tag: "direct", Protocol: "socks", Settings: map[string]any{"address": "1.2.3.4"}}, // Panel override
		},
	}

	cfg := buildConfig(kcfg, nc, testUsers, "", "")
	outbounds := cfg["outbounds"].([]M)

	// Since we overrode both 'direct' and 'block', the result should contain
	// exactly these two custom outbounds, without auto-generated defaults.
	if len(outbounds) != 2 {
		t.Errorf("outbounds: got %d, want 2", len(outbounds))
	}

	foundDirect := false
	foundBlock := false

	for _, o := range outbounds {
		tag := o["tag"].(string)
		if tag == "direct" {
			foundDirect = true
			if o["protocol"] != "socks" {
				t.Errorf("expected 'direct' protocol to be 'socks' (panel priority), got %v", o["protocol"])
			}
		}
		if tag == "block" {
			foundBlock = true
			if o["protocol"] != "dns" {
				t.Errorf("expected 'block' protocol to be 'dns' (static config priority), got %v", o["protocol"])
			}
		}
	}

	if !foundDirect || !foundBlock {
		t.Errorf("missing outbounds: direct=%v, block=%v", foundDirect, foundBlock)
	}
}

func TestBuildConfig_WithSOCKS5Proxy(t *testing.T) {
	kcfg := config.KernelConfig{
		Type:     "xray",
		LogLevel: "info",
	}
	kcfg.Egress.SOCKS5.Address = "127.0.0.1"
	kcfg.Egress.SOCKS5.Port = 1080

	nc := &panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 111,
		Cipher:     "aes-128-gcm",
	}

	cfg := buildConfig(kcfg, nc, testUsers, "", "")
	outbounds := cfg["outbounds"].([]M)
	foundProxy := false
	for _, outbound := range outbounds {
		if outbound["tag"] == config.DefaultSOCKS5ProxyTag {
			foundProxy = true
			if outbound["protocol"] != "socks" {
				t.Fatalf("expected socks outbound, got %v", outbound["protocol"])
			}
		}
	}
	if !foundProxy {
		t.Fatal("expected generated SOCKS5 outbound")
	}

	routing := cfg["routing"].(M)
	rules := routing["rules"].([]M)
	last := rules[len(rules)-1]
	if last["outboundTag"] != config.DefaultSOCKS5ProxyTag {
		t.Fatalf("expected default outbound tag %q, got %v", config.DefaultSOCKS5ProxyTag, last["outboundTag"])
	}
}

func TestBuildConfig_WithShadowsocksProxy(t *testing.T) {
	kcfg := config.KernelConfig{
		Type:     "xray",
		LogLevel: "info",
	}
	kcfg.Egress.Shadowsocks.Address = "127.0.0.1"
	kcfg.Egress.Shadowsocks.Port = 8388
	kcfg.Egress.Shadowsocks.Method = "aes-128-gcm"
	kcfg.Egress.Shadowsocks.Password = "test-password"

	nc := &panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 111,
		Cipher:     "aes-128-gcm",
	}

	cfg := buildConfig(kcfg, nc, testUsers, "", "")
	outbounds := cfg["outbounds"].([]M)
	foundProxy := false
	for _, outbound := range outbounds {
		if outbound["tag"] == config.DefaultShadowsocksProxyTag {
			foundProxy = true
			if outbound["protocol"] != "shadowsocks" {
				t.Fatalf("expected shadowsocks outbound, got %v", outbound["protocol"])
			}
			settings := outbound["settings"].(M)
			servers := settings["servers"].([]M)
			if len(servers) != 1 {
				t.Fatalf("expected 1 server, got %d", len(servers))
			}
			if servers[0]["method"] != "aes-128-gcm" {
				t.Fatalf("expected aes-128-gcm, got %v", servers[0]["method"])
			}
			if servers[0]["password"] != "test-password" {
				t.Fatalf("expected test-password, got %v", servers[0]["password"])
			}
		}
	}
	if !foundProxy {
		t.Fatal("expected generated Shadowsocks outbound")
	}

	routing := cfg["routing"].(M)
	rules := routing["rules"].([]M)
	last := rules[len(rules)-1]
	if last["outboundTag"] != config.DefaultShadowsocksProxyTag {
		t.Fatalf("expected default outbound tag %q, got %v", config.DefaultShadowsocksProxyTag, last["outboundTag"])
	}
}

func TestBuildConfig_WithShadowsocks2022Proxy(t *testing.T) {
	kcfg := config.KernelConfig{
		Type:     "xray",
		LogLevel: "info",
	}
	kcfg.Egress.Shadowsocks.Address = "cu1.utieol.com"
	kcfg.Egress.Shadowsocks.Port = 50552
	kcfg.Egress.Shadowsocks.Method = "2022-blake3-aes-256-gcm"
	kcfg.Egress.Shadowsocks.Password = "ZWNhZDc0OGIyMmRmYjlmNjliMzM1OTFmMDUwMmY5ZWU=:MDJiODI4NjctYTcwNS00ZTZkLWFjNzEtMDQ1ZjU0ZDY="

	nc := &panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 111,
		Cipher:     "aes-128-gcm",
	}

	cfg := buildConfig(kcfg, nc, testUsers, "", "")
	outbounds := cfg["outbounds"].([]M)
	for _, outbound := range outbounds {
		if outbound["tag"] == config.DefaultShadowsocksProxyTag {
			settings := outbound["settings"].(M)
			servers := settings["servers"].([]M)
			if servers[0]["method"] != "2022-blake3-aes-256-gcm" {
				t.Fatalf("expected 2022-blake3-aes-256-gcm, got %v", servers[0]["method"])
			}
			if servers[0]["password"] != "ZWNhZDc0OGIyMmRmYjlmNjliMzM1OTFmMDUwMmY5ZWU=:MDJiODI4NjctYTcwNS00ZTZkLWFjNzEtMDQ1ZjU0ZDY=" {
				t.Fatalf("unexpected ss2022 password: %v", servers[0]["password"])
			}
			return
		}
	}
	t.Fatal("expected generated Shadowsocks 2022 outbound")
}

func TestBuildConfig_AllProtocols_ValidJSON(t *testing.T) {
	protocols := []struct {
		name string
		nc   panel.NodeConfig
	}{
		{
			name: "vmess",
			nc: panel.NodeConfig{
				Protocol:   "vmess",
				ServerPort: 10086,
				Network:    "ws",
				TLS:        1,
				NetworkSettings: map[string]interface{}{
					"path": "/vmess",
					"host": "example.com",
				},
			},
		},
		{
			name: "vless",
			nc: panel.NodeConfig{
				Protocol:   "vless",
				ServerPort: 443,
				Network:    "tcp",
				TLS:        2,
				Flow:       "xtls-rprx-vision",
				TLSSettings: map[string]interface{}{
					"private_key": "test-pk",
					"short_id":    "abcd",
					"server_name": "www.example.com",
					"dest":        "www.example.com:443",
				},
			},
		},
		{
			name: "trojan",
			nc: panel.NodeConfig{
				Protocol:   "trojan",
				ServerPort: 443,
				Network:    "grpc",
				TLS:        1,
				ServerName: "example.com",
				NetworkSettings: map[string]interface{}{
					"service_name": "trojan-grpc",
				},
			},
		},
		{
			name: "shadowsocks-aes",
			nc: panel.NodeConfig{
				Protocol:   "shadowsocks",
				ServerPort: 8388,
				Cipher:     "aes-128-gcm",
			},
		},
		{
			name: "shadowsocks-2022",
			nc: panel.NodeConfig{
				Protocol:   "shadowsocks",
				ServerPort: 8388,
				Cipher:     "2022-blake3-aes-128-gcm",
				ServerKey:  "MDEyMzQ1Njc4OWFiY2RlZg==",
			},
		},
		{
			name: "socks",
			nc: panel.NodeConfig{
				Protocol:   "socks",
				ServerPort: 1080,
			},
		},
		{
			name: "http",
			nc: panel.NodeConfig{
				Protocol:   "http",
				ServerPort: 8080,
			},
		},
	}

	for _, tc := range protocols {
		t.Run(tc.name, func(t *testing.T) {
			cfg := buildConfig(testKernelCfg, &tc.nc, testUsers, "/cert.pem", "/key.pem")

			data, err := json.Marshal(cfg)
			if err != nil {
				t.Fatalf("marshal failed: %v", err)
			}

			var parsed map[string]interface{}
			if err := json.Unmarshal(data, &parsed); err != nil {
				t.Fatalf("invalid JSON: %v", err)
			}

			// Check required top-level fields
			for _, key := range []string{"log", "stats", "policy", "outbounds", "routing"} {
				if _, ok := parsed[key]; !ok {
					t.Errorf("missing top-level key: %s", key)
				}
			}

			if _, ok := parsed["inbounds"]; !ok {
				t.Error("missing inbounds")
			}

			t.Logf("config size: %d bytes", len(data))
		})
	}
}

func TestBuildConfig_VMess_Users(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "vmess",
		ServerPort: 10086,
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	inbounds := parsed["inbounds"].([]interface{})
	ib := inbounds[0].(map[string]interface{})

	if ib["protocol"] != "vmess" {
		t.Errorf("expected protocol vmess, got %v", ib["protocol"])
	}

	settings := ib["settings"].(map[string]interface{})
	clients := settings["clients"].([]interface{})

	if len(clients) != 2 {
		t.Fatalf("expected 2 clients, got %d", len(clients))
	}

	c1 := clients[0].(map[string]interface{})
	if c1["email"] != "user@1" {
		t.Errorf("expected email user@1, got %v", c1["email"])
	}
	if c1["id"] != "279d4f89-3a2c-488d-a67c-2d39a72acdde" {
		t.Errorf("unexpected UUID: %v", c1["id"])
	}
}

func TestBuildConfig_VLESS_Flow(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "vless",
		ServerPort: 443,
		Flow:       "xtls-rprx-vision",
		TLS:        2,
		TLSSettings: map[string]interface{}{
			"private_key": "pk",
			"server_name": "example.com",
		},
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	inbounds := parsed["inbounds"].([]interface{})
	ib := inbounds[0].(map[string]interface{})
	settings := ib["settings"].(map[string]interface{})
	clients := settings["clients"].([]interface{})
	c1 := clients[0].(map[string]interface{})

	if c1["flow"] != "xtls-rprx-vision" {
		t.Errorf("expected flow xtls-rprx-vision, got %v", c1["flow"])
	}

	ss := ib["streamSettings"].(map[string]interface{})
	if ss["security"] != "reality" {
		t.Errorf("expected security reality, got %v", ss["security"])
	}
}

func TestBuildRouting_Default(t *testing.T) {
	routing := buildRouting(config.KernelConfig{}, nil, nil)
	rules := routing["rules"].([]M)

	if len(rules) != 4 {
		t.Fatalf("expected 4 default rules, got %d", len(rules))
	}

	if rules[0]["outboundTag"] != "block" {
		t.Errorf("expected block outbound, got %v", rules[0]["outboundTag"])
	}
	ips := rules[0]["ip"].([]string)
	if len(ips) != 1 || ips[0] != "geoip:private" {
		t.Errorf("expected geoip:private block rule, got %v", ips)
	}
	if rules[3]["outboundTag"] != "direct" {
		t.Errorf("expected final direct rule, got %v", rules[3]["outboundTag"])
	}
}

func TestMergeCustomXrayRouting_AppendsAfterDefaultProtection(t *testing.T) {
	cfg := M{
		"routing": M{
			"rules": []M{
				{"type": "field", "ip": []string{"geoip:private"}, "outboundTag": "block"},
				{"type": "field", "protocol": []string{"bittorrent"}, "outboundTag": "block"},
			},
		},
	}

	mergeCustomXrayRouting(cfg, map[string]any{
		"rules": []map[string]any{
			{"type": "field", "domain": []string{"domain:example.com"}, "outboundTag": "direct"},
		},
	})

	rules := cfg["routing"].(M)["rules"].([]M)
	if len(rules) != 3 {
		t.Fatalf("rules: got %d, want 3", len(rules))
	}
	if rules[0]["outboundTag"] != "block" {
		t.Fatalf("expected default protection rule to stay first, got %#v", rules[0])
	}
	if rules[2]["outboundTag"] != "direct" {
		t.Fatalf("expected custom rule appended last, got %#v", rules[2])
	}
}

func TestBuildRouting_WithRules(t *testing.T) {
	rules := []panel.RouteRule{
		{
			ID:     1,
			Match:  []string{"*.baidu.com", "*.qq.com", "10.0.0.0/8"},
			Action: "block",
		},
		{
			ID:     2,
			Match:  []string{"*.google.com"},
			Action: "direct",
		},
	}

	routing := buildRouting(config.KernelConfig{}, rules, nil)
	xrayRules := routing["rules"].([]M)

	// 3 default protection rules + 2 panel rules + 1 panel IP rule + 1 catch-all rule = 7
	if len(xrayRules) != 7 {
		t.Fatalf("expected 7 rules, got %d", len(xrayRules))
	}

	// Rule 3: domains block
	r1 := xrayRules[3]
	domains := r1["domain"].([]string)
	if len(domains) != 2 {
		t.Fatalf("expected 2 domains, got %d", len(domains))
	}
	if domains[0] != "domain:baidu.com" || domains[1] != "domain:qq.com" {
		t.Errorf("unexpected domains: %v", domains)
	}
	if r1["outboundTag"] != "block" {
		t.Errorf("expected block, got %v", r1["outboundTag"])
	}

	// Rule 4: IP block
	r2 := xrayRules[4]
	ips := r2["ip"].([]string)
	if len(ips) != 1 || ips[0] != "10.0.0.0/8" {
		t.Errorf("unexpected IPs: %v", ips)
	}

	// Rule 5: direct
	r3 := xrayRules[5]
	if r3["outboundTag"] != "direct" {
		t.Errorf("expected direct, got %v", r3["outboundTag"])
	}

	// Rule 6: catch-all
	r4 := xrayRules[6]
	if r4["outboundTag"] != "direct" {
		t.Errorf("expected final direct catch-all, got %v", r4["outboundTag"])
	}
}

func TestBuildConfig_LogLevel(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"debug", "debug"},
		{"info", "info"},
		{"warn", "warning"},
		{"error", "error"},
		{"", "warning"},
	}

	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			result := xrayLogLevel(tc.input)
			if result != tc.expected {
				t.Errorf("xrayLogLevel(%q) = %q, want %q", tc.input, result, tc.expected)
			}
		})
	}
}

func TestBuildConfig_StatsEnabled(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "vmess",
		ServerPort: 10086,
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	// Verify stats is enabled
	if _, ok := parsed["stats"]; !ok {
		t.Error("stats not enabled")
	}

	// Verify policy enables user stats
	policy := parsed["policy"].(map[string]interface{})
	levels := policy["levels"].(map[string]interface{})
	level0 := levels["0"].(map[string]interface{})

	if v, ok := level0["statsUserUplink"]; !ok || v != true {
		t.Error("statsUserUplink not enabled")
	}
	if v, ok := level0["statsUserDownlink"]; !ok || v != true {
		t.Error("statsUserDownlink not enabled")
	}
}

func TestBuildConfig_Shadowsocks_SingleUser(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 8388,
		Cipher:     "aes-128-gcm",
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	inbounds := parsed["inbounds"].([]interface{})
	ib := inbounds[0].(map[string]interface{})
	settings := ib["settings"].(map[string]interface{})

	// Single-user mode: password directly, no clients array
	if settings["method"] != "aes-128-gcm" {
		t.Errorf("expected method aes-128-gcm, got %v", settings["method"])
	}
	if settings["password"] != testUsers[0].UUID {
		t.Errorf("expected password %s, got %v", testUsers[0].UUID, settings["password"])
	}
}

func TestBuildConfig_Shadowsocks_MultiUser(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "shadowsocks",
		ServerPort: 8388,
		Cipher:     "2022-blake3-aes-128-gcm",
		ServerKey:  "MDEyMzQ1Njc4OWFiY2RlZg==",
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	inbounds := parsed["inbounds"].([]interface{})
	ib := inbounds[0].(map[string]interface{})
	settings := ib["settings"].(map[string]interface{})

	if settings["password"] != "MDEyMzQ1Njc4OWFiY2RlZg==" {
		t.Errorf("expected server key, got %v", settings["password"])
	}
	clients := settings["clients"].([]interface{})
	if len(clients) != 2 {
		t.Fatalf("expected 2 clients, got %d", len(clients))
	}
}

func TestBuildConfig_SocksStats(t *testing.T) {
	nc := panel.NodeConfig{
		Protocol:   "socks",
		ServerPort: 1080,
	}
	cfg := buildConfig(testKernelCfg, &nc, testUsers, "", "")
	data, _ := json.Marshal(cfg)

	var parsed map[string]interface{}
	json.Unmarshal(data, &parsed)

	inbounds := parsed["inbounds"].([]interface{})
	ib := inbounds[0].(map[string]interface{})
	settings := ib["settings"].(map[string]interface{})
	accounts := settings["accounts"].([]interface{})

	if len(accounts) == 0 {
		t.Fatal("no accounts in socks config")
	}

	a1 := accounts[0].(map[string]interface{})
	if a1["email"] != "user@1" {
		t.Errorf("expected email user@1 for socks account, got %v", a1["email"])
	}
}
