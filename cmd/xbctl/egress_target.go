package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/micah123321/mi-node/internal/config"
)

type egressRow struct {
	ID       string `json:"id"`
	Mode     string `json:"mode"`
	Panel    string `json:"panel"`
	Target   string `json:"target"`
	Type     string `json:"type"`
	Upstream string `json:"upstream"`
	Auth     string `json:"auth"`
}

type egressTarget struct {
	ConfigPath string
	MetaPath   string
	InstanceID string
	PanelURL   string
	NodeID     int
	MachineID  int
	NoRestart  bool
}

func parseEgressTargetArgs(args []string) (egressTarget, error) {
	target := egressTarget{ConfigPath: defaultConfigPath, MetaPath: defaultMetaPath}
	for i := 0; i < len(args); i++ {
		next, consumed, err := parseEgressTargetArg(args, i, target)
		if err != nil {
			return target, err
		}
		if consumed == 0 {
			return target, fmt.Errorf("unknown egress clear arg: %s", args[i])
		}
		target = next
		i += consumed - 1
	}
	return target, nil
}

func parseEgressTargetArg(args []string, i int, target egressTarget) (egressTarget, int, error) {
	switch args[i] {
	case "--config":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --config")
		}
		target.ConfigPath = args[i+1]
		return target, 2, nil
	case "--meta":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --meta")
		}
		target.MetaPath = args[i+1]
		return target, 2, nil
	case "--instance-id", "--id":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --instance-id")
		}
		target.InstanceID = args[i+1]
		return target, 2, nil
	case "--panel-url", "--panel", "--api", "-a":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --panel-url")
		}
		target.PanelURL = args[i+1]
		return target, 2, nil
	case "--node-id", "-n":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --node-id")
		}
		v, err := parsePositiveInt(args[i+1], "node-id")
		if err != nil {
			return target, 0, err
		}
		target.NodeID = v
		return target, 2, nil
	case "--machine-id":
		if i+1 >= len(args) {
			return target, 0, errors.New("missing value for --machine-id")
		}
		v, err := parsePositiveInt(args[i+1], "machine-id")
		if err != nil {
			return target, 0, err
		}
		target.MachineID = v
		return target, 2, nil
	case "--no-restart":
		target.NoRestart = true
		return target, 1, nil
	default:
		return target, 0, nil
	}
}

func loadEgressTarget(target egressTarget) (*config.RootConfig, []config.Config, int, error) {
	root, err := loadWritableRootConfig(target.ConfigPath)
	if err != nil {
		return nil, nil, -1, err
	}
	instances := normalizeWritableInstances(root)
	if len(instances) == 0 {
		return nil, nil, -1, errors.New("no instances configured")
	}
	idx, err := findEgressTarget(instances, target)
	if err != nil {
		return nil, nil, -1, err
	}
	return root, instances, idx, nil
}

func normalizeWritableInstances(root *config.RootConfig) []config.Config {
	instances := normalizeRootInstances(root)
	for i := range instances {
		if id, err := instances[i].AutoInstanceID(); err == nil && id != "" {
			instances[i].InstanceID = id
		}
	}
	return instances
}

func findEgressTarget(instances []config.Config, target egressTarget) (int, error) {
	var matches []int
	for i, inst := range instances {
		matched := true
		if target.InstanceID != "" {
			matched = inst.InstanceID == target.InstanceID
		}
		if target.PanelURL != "" {
			matched = matched && strings.TrimSpace(inst.Panel.URL) == strings.TrimSpace(target.PanelURL)
		}
		if target.NodeID > 0 {
			matched = matched && !inst.IsMachineMode() && inst.Panel.NodeID == target.NodeID
		}
		if target.MachineID > 0 {
			matched = matched && inst.IsMachineMode() && inst.Machine != nil && inst.Machine.MachineID == target.MachineID
		}
		if target.InstanceID == "" && target.PanelURL == "" && target.NodeID == 0 && target.MachineID == 0 {
			matched = len(instances) == 1
		}
		if matched {
			matches = append(matches, i)
		}
	}
	if len(matches) == 0 {
		return -1, errors.New("target instance not found")
	}
	if len(matches) > 1 {
		return -1, errors.New("multiple instances matched; add --instance-id or --panel-url to select one")
	}
	return matches[0], nil
}

func printEgressRows(rows []egressRow, output string) error {
	if output == "json" {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(rows)
	}
	var buf bytes.Buffer
	tw := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tMODE\tPANEL\tTARGET\tTYPE\tUPSTREAM\tAUTH")
	for _, row := range rows {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", row.ID, row.Mode, row.Panel, row.Target, row.Type, row.Upstream, row.Auth)
	}
	tw.Flush()
	_, err := fmt.Print(buf.String())
	return err
}

func egressSummary(egress config.EgressConfig) (string, string, string) {
	if egress.SOCKS5.Address != "" || egress.SOCKS5.Port > 0 {
		auth := "no"
		if egress.SOCKS5.Username != "" || egress.SOCKS5.Password != "" {
			auth = "yes"
		}
		return "socks5", fmt.Sprintf("%s:%d", egress.SOCKS5.Address, egress.SOCKS5.Port), auth
	}
	if strings.TrimSpace(egress.Shadowsocks.URI) != "" {
		return "shadowsocks", sanitizedShadowsocksUpstream(egress.Shadowsocks.URI), "yes"
	}
	return "direct", "-", "no"
}

func sanitizedShadowsocksUpstream(raw string) string {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Host == "" {
		return "configured"
	}
	return parsed.Host
}
