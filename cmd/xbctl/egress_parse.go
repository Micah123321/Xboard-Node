package main

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"strings"

	"github.com/micah123321/mi-node/internal/config"
)

type egressSetOptions struct {
	egressTarget
	SOCKS5URL      string
	SOCKS5Endpoint string
	SOCKS5User     string
	SOCKS5Pass     string
	ShadowsocksURI string
}

func parseEgressSetArgs(args []string) (egressSetOptions, error) {
	opts := egressSetOptions{
		egressTarget: egressTarget{ConfigPath: defaultConfigPath, MetaPath: defaultMetaPath},
	}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--socks5-url":
			i++
			if i >= len(args) {
				return opts, errors.New("missing value for --socks5-url")
			}
			opts.SOCKS5URL = args[i]
		case "--socks5":
			i++
			if i >= len(args) {
				return opts, errors.New("missing value for --socks5")
			}
			opts.SOCKS5Endpoint = args[i]
		case "--socks5-user":
			i++
			if i >= len(args) {
				return opts, errors.New("missing value for --socks5-user")
			}
			opts.SOCKS5User = args[i]
		case "--socks5-pass":
			i++
			if i >= len(args) {
				return opts, errors.New("missing value for --socks5-pass")
			}
			opts.SOCKS5Pass = args[i]
		case "--shadowsocks-uri", "--ss-uri":
			i++
			if i >= len(args) {
				return opts, errors.New("missing value for --shadowsocks-uri")
			}
			opts.ShadowsocksURI = args[i]
		default:
			target, consumed, err := parseEgressTargetArg(args, i, opts.egressTarget)
			if err != nil {
				return opts, err
			}
			if consumed == 0 {
				return opts, fmt.Errorf("unknown egress set arg: %s", args[i])
			}
			opts.egressTarget = target
			i += consumed - 1
		}
	}
	return opts, nil
}

func buildEgressConfig(opts egressSetOptions, kernelType string) (config.EgressConfig, string, error) {
	hasSOCKS5 := opts.SOCKS5URL != "" || opts.SOCKS5Endpoint != "" || opts.SOCKS5User != "" || opts.SOCKS5Pass != ""
	hasSS := opts.ShadowsocksURI != ""
	if hasSOCKS5 && hasSS {
		return config.EgressConfig{}, "", errors.New("SOCKS5 and Shadowsocks egress are mutually exclusive")
	}
	if !hasSOCKS5 && !hasSS {
		return config.EgressConfig{}, "", errors.New("usage: xbctl egress set <target> (--socks5-url URL | --socks5 HOST:PORT | --shadowsocks-uri URI)")
	}

	enableDefaultRules := true
	preferIPv4 := true
	egress := config.EgressConfig{
		EnableDefaultRules: &enableDefaultRules,
		PreferIPv4:         &preferIPv4,
	}
	if hasSS {
		egress.Shadowsocks.URI = strings.TrimSpace(opts.ShadowsocksURI)
		if err := validateEgressForKernel(&egress, kernelType); err != nil {
			return config.EgressConfig{}, "", err
		}
		return egress, fmt.Sprintf("shadowsocks %s", sanitizedShadowsocksUpstream(opts.ShadowsocksURI)), nil
	}

	socks, err := buildSOCKS5Config(opts)
	if err != nil {
		return config.EgressConfig{}, "", err
	}
	egress.SOCKS5 = socks
	if err := validateEgressForKernel(&egress, kernelType); err != nil {
		return config.EgressConfig{}, "", err
	}
	auth := "no-auth"
	if socks.Username != "" || socks.Password != "" {
		auth = "auth"
	}
	return egress, fmt.Sprintf("socks5 %s:%d %s", socks.Address, socks.Port, auth), nil
}

func buildSOCKS5Config(opts egressSetOptions) (config.SOCKS5EgressConfig, error) {
	var socks config.SOCKS5EgressConfig
	var err error
	if opts.SOCKS5URL != "" {
		socks, err = parseSOCKS5URL(opts.SOCKS5URL)
		if err != nil {
			return config.SOCKS5EgressConfig{}, err
		}
	} else {
		host, port, endpointErr := parseSOCKS5Endpoint(opts.SOCKS5Endpoint)
		if endpointErr != nil {
			return config.SOCKS5EgressConfig{}, endpointErr
		}
		socks.Address = host
		socks.Port = port
	}
	if opts.SOCKS5User != "" || opts.SOCKS5Pass != "" {
		socks.Username = opts.SOCKS5User
		socks.Password = opts.SOCKS5Pass
	}
	return socks, nil
}

func validateEgressForKernel(egress *config.EgressConfig, kernelType string) error {
	if kernelType == "" {
		kernelType = "singbox"
	}
	return egress.Validate(kernelType)
}

func parseSOCKS5URL(raw string) (config.SOCKS5EgressConfig, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return config.SOCKS5EgressConfig{}, err
	}
	if parsed.Scheme != "socks5" && parsed.Scheme != "socks" {
		return config.SOCKS5EgressConfig{}, fmt.Errorf("expected socks5:// URI, got %q", parsed.Scheme)
	}
	host := parsed.Hostname()
	if host == "" {
		return config.SOCKS5EgressConfig{}, errors.New("SOCKS5 URI missing host")
	}
	port, err := parsePositiveInt(parsed.Port(), "socks5 port")
	if err != nil {
		return config.SOCKS5EgressConfig{}, err
	}
	socks := config.SOCKS5EgressConfig{
		Address:  host,
		Port:     port,
		Username: parsed.User.Username(),
	}
	if password, ok := parsed.User.Password(); ok {
		socks.Password = password
	}
	return socks, nil
}

func parseSOCKS5Endpoint(raw string) (string, int, error) {
	host, portRaw, err := net.SplitHostPort(strings.TrimSpace(raw))
	if err != nil {
		return "", 0, fmt.Errorf("--socks5 must be host:port or [ipv6]:port: %w", err)
	}
	port, err := parsePositiveInt(portRaw, "socks5 port")
	if err != nil {
		return "", 0, err
	}
	return host, port, nil
}
