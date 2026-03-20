package config

import "fmt"

const DefaultSOCKS5ProxyTag = "default-socks5"

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
}

// SOCKS5EgressConfig describes a default upstream SOCKS5 proxy.
type SOCKS5EgressConfig struct {
	Address  string `yaml:"address"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username,omitempty"`
	Password string `yaml:"password,omitempty"`
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
	return c.SOCKS5.Address != "" && c.SOCKS5.Port > 0
}

// DefaultOutboundTag returns the default final outbound tag for generated
// routing rules.
func (c EgressConfig) DefaultOutboundTag() string {
	if c.ProxyEnabled() {
		return DefaultSOCKS5ProxyTag
	}
	return "direct"
}

// Validate checks that optional SOCKS5 upstream fields are complete.
func (c EgressConfig) Validate() error {
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
	if (hasUsername || hasPassword) && !c.ProxyEnabled() {
		return fmt.Errorf("egress.socks5.address and egress.socks5.port are required when SOCKS5 authentication is configured")
	}

	return nil
}
