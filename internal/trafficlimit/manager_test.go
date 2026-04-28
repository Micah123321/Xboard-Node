package trafficlimit

import (
	"path/filepath"
	"testing"
	"time"
)

func TestManagerSuspendsAndPersists(t *testing.T) {
	now := time.Date(2026, 4, 28, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "traffic-limit.json")
	manager := New(path, func() time.Time { return now })

	action, err := manager.Configure(Config{
		Enabled:   true,
		Limit:     100,
		ResetDay:  1,
		ResetTime: "00:00",
		Timezone:  "UTC",
	})
	if err != nil {
		t.Fatalf("Configure() error = %v", err)
	}
	if action != ActionNone {
		t.Fatalf("Configure() action = %v, want ActionNone", action)
	}

	action, err = manager.AddTraffic(40, 61)
	if err != nil {
		t.Fatalf("AddTraffic() error = %v", err)
	}
	if action != ActionSuspend {
		t.Fatalf("AddTraffic() action = %v, want ActionSuspend", action)
	}
	if manager.CanRun() {
		t.Fatalf("CanRun() = true, want false")
	}

	restored := New(path, func() time.Time { return now })
	if action, err := restored.Configure(Config{Enabled: true, Limit: 100, ResetDay: 1, ResetTime: "00:00", Timezone: "UTC"}); err != nil || action != ActionNone {
		t.Fatalf("restored Configure() action = %v error = %v, want no transition without error", action, err)
	}
	if restored.CanRun() {
		t.Fatalf("restored CanRun() = true, want false")
	}
}

func TestManagerResetsWhenDue(t *testing.T) {
	now := time.Date(2026, 4, 1, 0, 0, 1, 0, time.UTC)
	manager := New(filepath.Join(t.TempDir(), "traffic-limit.json"), func() time.Time { return now })

	_, err := manager.Configure(Config{
		Enabled:     true,
		Limit:       100,
		ResetDay:    1,
		ResetTime:   "00:00",
		Timezone:    "UTC",
		CurrentUsed: 120,
		NextResetAt: time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC).Unix(),
	})
	if err != nil {
		t.Fatalf("Configure() error = %v", err)
	}

	snapshot := manager.Snapshot()
	if snapshot.Suspended {
		t.Fatalf("Snapshot().Suspended = true, want false after due reset")
	}
	if snapshot.Used != 0 {
		t.Fatalf("Snapshot().Used = %d, want 0", snapshot.Used)
	}
	if snapshot.NextResetAt <= now.Unix() {
		t.Fatalf("NextResetAt = %d, want future timestamp", snapshot.NextResetAt)
	}
}

func TestManagerClampsMissingDayToEndOfMonth(t *testing.T) {
	now := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)
	manager := New("", func() time.Time { return now })

	if _, err := manager.Configure(Config{Enabled: true, Limit: 1, ResetDay: 31, ResetTime: "03:30", Timezone: "UTC"}); err != nil {
		t.Fatalf("Configure() error = %v", err)
	}

	got := time.Unix(manager.Snapshot().NextResetAt, 0).UTC()
	want := time.Date(2026, 2, 28, 3, 30, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("NextResetAt = %s, want %s", got, want)
	}
}

func TestManagerPanelResetResumes(t *testing.T) {
	now := time.Date(2026, 4, 28, 12, 0, 0, 0, time.UTC)
	manager := New("", func() time.Time { return now })

	if action, err := manager.Configure(Config{Enabled: true, Limit: 100, CurrentUsed: 120, ResetDay: 1, ResetTime: "00:00", Timezone: "UTC"}); err != nil || action != ActionSuspend {
		t.Fatalf("Configure() action = %v error = %v, want suspend without error", action, err)
	}

	action, err := manager.Configure(Config{
		Enabled:     true,
		Limit:       100,
		CurrentUsed: 0,
		LastResetAt: now.Unix() + 1,
		ResetDay:    1,
		ResetTime:   "00:00",
		Timezone:    "UTC",
	})
	if err != nil {
		t.Fatalf("Configure(reset) error = %v", err)
	}
	if action != ActionResume {
		t.Fatalf("Configure(reset) action = %v, want ActionResume", action)
	}
	if !manager.CanRun() {
		t.Fatalf("CanRun() = false, want true")
	}
}
