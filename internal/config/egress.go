package config

import (
	"encoding/base64"
	"fmt"
	"strings"
)

const DefaultSOCKS5ProxyTag = "default-socks5"
const DefaultShadowsocksProxyTag = "default-shadowsocks"

var supportedShadowsocksMethods = map[string]struct{}{
	"aes-128-gcm":             {},
	"aes-192-gcm":             {},
	"aes-256-gcm":             {},
	"chacha20-ietf-poly1305":  {},
	"2022-blake3-aes-128-gcm": {},
	"2022-blake3-aes-256-gcm": {},
}

// EgressConfig controls outbound proxying and built-in abuse-prevention rules.
type EgressConfig struct {
	// EnableDefaultRules prepends a maintained blocklist and private-network
	// protection rules to all generated kernel configs.
	EnableDefaultRules *bool `yaml:"enable_default_rules,omitempty"`

	// PreferIPv4 applies the repository's IPv4-first egress strategy where the
	// underlying kernel supports it.
	PreferIPv4 *bool `yaml:"prefer_ipv4,omitempty"`

	// SOCKS5 configures a default upstream SOCKS5 outbound. When set, the
	// generated routing rules send ordinary TCP/UDP traffic through this proxy.
	SOCKS5 SOCKS5EgressConfig `yaml:"socks5"`

	// Shadowsocks configures a default upstream Shadowsocks outbound. When set,
	// the generated routing rules send ordinary TCP/UDP traffic through this proxy.
	Shadowsocks ShadowsocksEgressConfig `yaml:"shadowsocks"`
}

// SOCKS5EgressConfig describes a default upstream SOCKS5 proxy.
type SOCKS5EgressConfig struct {
	Address  string `yaml:"address"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username,omitempty"`
	Password string `yaml:"password,omitempty"`
}

// ShadowsocksEgressConfig describes a default upstream Shadowsocks proxy.
type ShadowsocksEgressConfig struct {
	Address  string `yaml:"address"`
	Port     int    `yaml:"port"`
	Method   string `yaml:"method"`
	Password string `yaml:"password"`
}

func (c *EgressConfig) setDefaults() {}

// DefaultRulesEnabled reports whether the maintained abuse-prevention rules
// should be applied. The default is true.
func (c EgressConfig) DefaultRulesEnabled() bool {
	if c.EnableDefaultRules == nil {
		return true
	}
	return *c.EnableDefaultRules
}

// IPv4Preferred reports whether the built-in IPv4-first egress strategy
// should be enabled. The default is true.
func (c EgressConfig) IPv4Preferred() bool {
	if c.PreferIPv4 == nil {
		return true
	}
	return *c.PreferIPv4
}

// ProxyEnabled reports whether a complete SOCKS5 upstream proxy has been set.
func (c EgressConfig) ProxyEnabled() bool {
	return c.SOCKS5Enabled() || c.ShadowsocksEnabled()
}

// SOCKS5Enabled reports whether a complete SOCKS5 upstream proxy has been set.
func (c EgressConfig) SOCKS5Enabled() bool {
	return c.SOCKS5.Address != "" && c.SOCKS5.Port > 0
}

// ShadowsocksEnabled reports whether a complete Shadowsocks upstream proxy has
// been set.
func (c EgressConfig) ShadowsocksEnabled() bool {
	return c.Shadowsocks.Address != "" &&
		c.Shadowsocks.Port > 0 &&
		c.Shadowsocks.Method != "" &&
		c.Shadowsocks.Password != ""
}

// DefaultOutboundTag returns the default final outbound tag for generated
// routing rules.
func (c EgressConfig) DefaultOutboundTag() string {
	if c.SOCKS5Enabled() {
		return DefaultSOCKS5ProxyTag
	}
	if c.ShadowsocksEnabled() {
		return DefaultShadowsocksProxyTag
	}
	return "direct"
}

// Validate checks that optional upstream fields are complete and compatible
// with the selected kernel.
func (c EgressConfig) Validate(kernelType string) error {
	hasAddress := c.SOCKS5.Address != ""
	hasPort := c.SOCKS5.Port != 0

	if hasAddress != hasPort {
		return fmt.Errorf("egress.socks5.address and egress.socks5.port must be set together")
	}
	if c.SOCKS5.Port < 0 {
		return fmt.Errorf("egress.socks5.port must not be negative")
	}

	hasUsername := c.SOCKS5.Username != ""
	hasPassword := c.SOCKS5.Password != ""
	if hasUsername != hasPassword {
		return fmt.Errorf("egress.socks5.username and egress.socks5.password must be set together")
	}
	if (hasUsername || hasPassword) && !c.SOCKS5Enabled() {
		return fmt.Errorf("egress.socks5.address and egress.socks5.port are required when SOCKS5 authentication is configured")
	}

	hasSSAddress := c.Shadowsocks.Address != ""
	hasSSPort := c.Shadowsocks.Port != 0
	if hasSSAddress != hasSSPort {
		return fmt.Errorf("egress.shadowsocks.address and egress.shadowsocks.port must be set together")
	}
	if c.Shadowsocks.Port < 0 {
		return fmt.Errorf("egress.shadowsocks.port must not be negative")
	}

	hasSSMethod := c.Shadowsocks.Method != ""
	hasSSPassword := c.Shadowsocks.Password != ""
	if hasSSMethod != hasSSPassword {
		return fmt.Errorf("egress.shadowsocks.method and egress.shadowsocks.password must be set together")
	}
	if (hasSSAddress || hasSSPort) && !(hasSSMethod && hasSSPassword) {
		return fmt.Errorf("egress.shadowsocks.method and egress.shadowsocks.password are required when egress.shadowsocks.address and egress.shadowsocks.port are configured")
	}
	if (hasSSMethod || hasSSPassword) && !(hasSSAddress && hasSSPort) {
		return fmt.Errorf("egress.shadowsocks.address and egress.shadowsocks.port are required when Shadowsocks authentication is configured")
	}
	if hasSSMethod {
		if err := validateEgressShadowsocksMethod(c.Shadowsocks.Method); err != nil {
			return err
		}
		if err := validateEgressShadowsocksMethodForKernel(kernelType, c.Shadowsocks.Method); err != nil {
			return err
		}
	}
	if c.ShadowsocksEnabled() {
		if err := validateEgressShadowsocksPassword(c.Shadowsocks.Method, c.Shadowsocks.Password); err != nil {
			return fmt.Errorf("invalid egress.shadowsocks.password: %w", err)
		}
	}

	if c.SOCKS5Enabled() && c.ShadowsocksEnabled() {
		return fmt.Errorf("egress.socks5 and egress.shadowsocks are mutually exclusive")
	}

	return nil
}

func validateEgressShadowsocksMethod(method string) error {
	if _, ok := supportedShadowsocksMethods[method]; !ok {
		return fmt.Errorf("unsupported egress.shadowsocks.method %q", method)
	}
	return nil
}

func validateEgressShadowsocksMethodForKernel(kernelType, method string) error {
	if kernelType == "xray" && method == "aes-192-gcm" {
		return fmt.Errorf("egress.shadowsocks.method %q is not supported when kernel.type is %q", method, kernelType)
	}
	return nil
}

func validateEgressShadowsocksPassword(method, password string) error {
	if !strings.HasPrefix(method, "2022-blake3-") {
		return nil
	}

	keyLength, err := shadowsocks2022KeyLength(method)
	if err != nil {
		return err
	}

	parts := strings.Split(password, ":")
	switch len(parts) {
	case 1:
		return validateShadowsocks2022Key(parts[0], keyLength)
	case 2:
		if err := validateShadowsocks2022Key(parts[0], keyLength); err != nil {
			return fmt.Errorf("server key: %w", err)
		}
		if err := validateShadowsocks2022Key(parts[1], keyLength); err != nil {
			return fmt.Errorf("user key: %w", err)
		}
		return nil
	default:
		return fmt.Errorf("expected <server_key> or <server_key>:<user_key> for %s", method)
	}
}

func shadowsocks2022KeyLength(cipher string) (int, error) {
	switch cipher {
	case "2022-blake3-aes-128-gcm":
		return 16, nil
	case "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305":
		return 32, nil
	default:
		return 0, fmt.Errorf("unsupported shadowsocks 2022 cipher %q", cipher)
	}
}

func validateShadowsocks2022Key(value string, keyLength int) error {
	if value == "" {
		return fmt.Errorf("empty value, expected standard base64 for a %d-byte key", keyLength)
	}

	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return fmt.Errorf("must be standard base64 for a %d-byte key: %w", keyLength, err)
	}

	if len(decoded) != keyLength {
		return fmt.Errorf("expected %d-byte key after base64 decode, got %d bytes", keyLength, len(decoded))
	}

	return nil
}
