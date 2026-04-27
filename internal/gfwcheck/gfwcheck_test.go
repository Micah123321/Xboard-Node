package gfwcheck

import "testing"

func TestClassifyBlockedWhenAllTargetsTimeout(t *testing.T) {
	operators := map[string]OperatorResult{
		"ct": {Targets: []TargetResult{{Status: "timeout"}}},
		"cu": {Targets: []TargetResult{{Status: "timeout"}}},
		"cm": {Targets: []TargetResult{{Status: "timeout"}}},
	}

	summary := summarize(operators)
	if got := classify(operators, summary); got != StatusBlocked {
		t.Fatalf("expected %s, got %s", StatusBlocked, got)
	}
}

func TestClassifyNormalWhenAllOperatorsReachable(t *testing.T) {
	operators := map[string]OperatorResult{
		"ct": {Targets: []TargetResult{{Status: "ok", LatencyMS: 10}, {Status: "timeout"}}},
		"cu": {Targets: []TargetResult{{Status: "ok", LatencyMS: 20}}},
		"cm": {Targets: []TargetResult{{Status: "ok", LatencyMS: 30}}},
	}

	summary := summarize(operators)
	if got := classify(operators, summary); got != StatusNormal {
		t.Fatalf("expected %s, got %s", StatusNormal, got)
	}
}

func TestClassifyPartialWhenOnlySomeOperatorsReachable(t *testing.T) {
	operators := map[string]OperatorResult{
		"ct": {Targets: []TargetResult{{Status: "ok", LatencyMS: 10}}},
		"cu": {Targets: []TargetResult{{Status: "timeout"}}},
		"cm": {Targets: []TargetResult{{Status: "timeout"}}},
	}

	summary := summarize(operators)
	if got := classify(operators, summary); got != StatusPartial {
		t.Fatalf("expected %s, got %s", StatusPartial, got)
	}
}

func TestParseAverageLatencyFromLinuxPing(t *testing.T) {
	output := "rtt min/avg/max/mdev = 1.234/5.678/9.012/0.345 ms"
	if got := parseAverageLatency(output); got != 5.678 {
		t.Fatalf("expected 5.678, got %v", got)
	}
}

func TestParseAverageLatencyFromWindowsPing(t *testing.T) {
	output := "Minimum = 1ms, Maximum = 10ms, Average = 4ms"
	if got := parseAverageLatency(output); got != 4 {
		t.Fatalf("expected 4, got %v", got)
	}
}
