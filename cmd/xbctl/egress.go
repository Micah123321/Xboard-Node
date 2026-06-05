package main

import (
	"errors"
	"fmt"
	"sort"

	"github.com/micah123321/mi-node/internal/config"
)

func runEgress(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: xbctl egress <list|set|clear>")
	}
	switch args[0] {
	case "list":
		return runEgressList(args[1:])
	case "set":
		return runEgressSet(args[1:])
	case "clear":
		return runEgressClear(args[1:])
	default:
		return fmt.Errorf("unknown egress command: %s", args[0])
	}
}

func runEgressList(args []string) error {
	cfgPath := defaultConfigPath
	output := parseOutput(args)
	for i := 0; i < len(args); i++ {
		if args[i] == "--config" {
			if i+1 >= len(args) {
				return errors.New("missing value for --config")
			}
			i++
			cfgPath = args[i]
		}
	}

	root, err := loadWritableRootConfig(cfgPath)
	if err != nil {
		return err
	}
	instances := normalizeWritableInstances(root)
	rows := make([]egressRow, 0, len(instances))
	for _, inst := range instances {
		typ, upstream, auth := egressSummary(inst.Kernel.Egress)
		rows = append(rows, egressRow{
			ID:       inst.InstanceID,
			Mode:     instanceMode(inst),
			Panel:    inst.Panel.URL,
			Target:   formatTarget(intPtr(inst.Panel.NodeID), machineIDPtr(&inst)),
			Type:     typ,
			Upstream: upstream,
			Auth:     auth,
		})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].ID < rows[j].ID })
	return printEgressRows(rows, output)
}

func runEgressSet(args []string) error {
	opts, err := parseEgressSetArgs(args)
	if err != nil {
		return err
	}
	root, instances, idx, err := loadEgressTarget(opts.egressTarget)
	if err != nil {
		return err
	}
	egress, summary, err := buildEgressConfig(opts, instances[idx].Kernel.Type)
	if err != nil {
		return err
	}
	instances[idx].Kernel.Egress = egress
	root.Instances = instances
	if err := writeRootConfig(opts.ConfigPath, root); err != nil {
		return err
	}
	if err := writeInstallMeta(opts.MetaPath, root); err != nil {
		return err
	}
	if !opts.NoRestart {
		if err := runServiceCommand("restart"); err != nil {
			return err
		}
	}
	fmt.Printf("egress updated: %s %s\n", instances[idx].InstanceID, summary)
	return nil
}

func runEgressClear(args []string) error {
	target, err := parseEgressTargetArgs(args)
	if err != nil {
		return err
	}
	root, instances, idx, err := loadEgressTarget(target)
	if err != nil {
		return err
	}
	instances[idx].Kernel.Egress = config.EgressConfig{}
	root.Instances = instances
	if err := writeRootConfig(target.ConfigPath, root); err != nil {
		return err
	}
	if err := writeInstallMeta(target.MetaPath, root); err != nil {
		return err
	}
	if !target.NoRestart {
		if err := runServiceCommand("restart"); err != nil {
			return err
		}
	}
	fmt.Printf("egress cleared: %s\n", instances[idx].InstanceID)
	return nil
}
