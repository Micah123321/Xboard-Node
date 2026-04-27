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
