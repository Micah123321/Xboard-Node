package config

import (
	"context"
	"log/slog"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Watcher reloads the config file on change (debounced) and calls onChange.
type Watcher struct {
	path         string
	onChange     func(*Config)
	onChangeRoot func(*RootConfig)
	watcher      *fsnotify.Watcher

	stopOnce sync.Once
	stopCh   chan struct{}
	stopped  atomic.Bool

	debounceNanos atomic.Int64
}

// WatchConfig watches path; invalid reloads are logged and ignored.
// Stop via Stop() or cancel ctx.
func WatchConfig(ctx context.Context, path string, onChange func(*Config)) (*Watcher, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}

	fsw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}

	// Watch the parent directory so atomic save patterns are observable.
	dir := filepath.Dir(absPath)
	if err := fsw.Add(dir); err != nil {
		fsw.Close()
		return nil, err
	}

	w := &Watcher{
		path:     absPath,
		onChange: onChange,
		watcher:  fsw,
		stopCh:   make(chan struct{}),
	}
	w.SetDebounce(time.Second)

	go w.loop(ctx)
	slog.Info("config watcher started", "path", absPath)
	return w, nil
}

// WatchConfigRoot watches path and reloads the root config model.
func WatchConfigRoot(ctx context.Context, path string, onChange func(*RootConfig)) (*Watcher, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}

	fsw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}

	dir := filepath.Dir(absPath)
	if err := fsw.Add(dir); err != nil {
		fsw.Close()
		return nil, err
	}

	w := &Watcher{
		path:         absPath,
		onChangeRoot: onChange,
		watcher:      fsw,
		stopCh:       make(chan struct{}),
	}
	w.SetDebounce(time.Second)

	go w.loop(ctx)
	slog.Info("config watcher started", "path", absPath)
	return w, nil
}

func (w *Watcher) loop(ctx context.Context) {
	var timer *time.Timer
	defer func() {
		if timer != nil {
			timer.Stop()
		}
		w.watcher.Close()
	}()

	for {
		select {
		case <-ctx.Done():
			return
		case <-w.stopCh:
			return
		case ev, ok := <-w.watcher.Events:
			if !ok {
				return
			}
			if filepath.Clean(ev.Name) != w.path {
				continue
			}
			if !ev.Has(fsnotify.Write) && !ev.Has(fsnotify.Create) && !ev.Has(fsnotify.Rename) {
				continue
			}

			debounce := w.debounce()
			if timer == nil {
				timer = time.AfterFunc(debounce, w.reload)
			} else {
				timer.Reset(debounce)
			}
		case err, ok := <-w.watcher.Errors:
			if !ok {
				return
			}
			slog.Warn("config watcher error", "error", err)
		}
	}
}

func (w *Watcher) reload() {
	if w.stopped.Load() {
		return
	}

	if w.onChangeRoot != nil {
		root, err := LoadRoot(w.path)
		if err != nil {
			slog.Error("config reload failed, keeping current config", "error", err)
			return
		}

		slog.Info("config reloaded successfully")
		w.onChangeRoot(root)
		return
	}

	cfg, err := Load(w.path)
	if err != nil {
		slog.Error("config reload failed, keeping current config", "error", err)
		return
	}

	slog.Info("config reloaded successfully")
	w.onChange(cfg)
}

func (w *Watcher) Stop() {
	w.stopped.Store(true)
	w.stopOnce.Do(func() { close(w.stopCh) })
}

func (w *Watcher) SetDebounce(delay time.Duration) {
	if delay <= 0 {
		delay = time.Second
	}
	w.debounceNanos.Store(int64(delay))
}

func (w *Watcher) debounce() time.Duration {
	delay := time.Duration(w.debounceNanos.Load())
	if delay <= 0 {
		return time.Second
	}
	return delay
}
