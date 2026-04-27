package gfwcheck

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"sync"
	"time"
)

const (
	StatusNormal  = "normal"
	StatusBlocked = "blocked"
	StatusPartial = "partial"
	StatusFailed  = "failed"
)

type Target struct {
	Name string `json:"name"`
	Host string `json:"host"`
}

type Task struct {
	CheckID        int64               `json:"check_id"`
	Targets        map[string][]Target `json:"targets"`
	PingCount      int                 `json:"ping_count"`
	TimeoutSeconds int                 `json:"timeout_seconds"`
	Parallel       int                 `json:"parallel"`
}

type Report struct {
	CheckID         int64                     `json:"check_id"`
	Status          string                    `json:"status"`
	Summary         Summary                   `json:"summary"`
	OperatorSummary map[string]OperatorResult `json:"operator_summary"`
	RawResult       map[string]any            `json:"raw_result"`
	ErrorMessage    string                    `json:"error_message,omitempty"`
}

type Summary struct {
	Status       string  `json:"status"`
	Total        int     `json:"total"`
	Success      int     `json:"success"`
	Timeout      int     `json:"timeout"`
	TimeoutRatio float64 `json:"timeout_ratio"`
}

type OperatorResult struct {
	Total     int            `json:"total"`
	Success   int            `json:"success"`
	Timeout   int            `json:"timeout"`
	AverageMS float64        `json:"average_ms"`
	MinMS     float64        `json:"min_ms"`
	MaxMS     float64        `json:"max_ms"`
	Slowest   string         `json:"slowest,omitempty"`
	Targets   []TargetResult `json:"targets"`
}

type TargetResult struct {
	Name      string  `json:"name"`
	Host      string  `json:"host"`
	Status    string  `json:"status"`
	LatencyMS float64 `json:"latency_ms,omitempty"`
	Error     string  `json:"error,omitempty"`
}

type targetJob struct {
	operator string
	target   Target
}

type targetOutput struct {
	operator string
	result   TargetResult
}

var latencyPatterns = []struct {
	re    *regexp.Regexp
	group int
}{
	{regexp.MustCompile(`=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/[0-9.]+)?`), 2},
	{regexp.MustCompile(`(?i)Average\s*=\s*([0-9.]+)\s*ms`), 1},
}

func Run(ctx context.Context, task Task) Report {
	if task.CheckID <= 0 {
		return failedReport(task.CheckID, "check_id is required")
	}
	if _, err := exec.LookPath("ping"); err != nil {
		return failedReport(task.CheckID, "ping command not found")
	}

	task = normalizeTask(task)
	jobs := make([]targetJob, 0)
	for operator, targets := range task.Targets {
		for _, target := range targets {
			if target.Host == "" {
				continue
			}
			jobs = append(jobs, targetJob{operator: operator, target: target})
		}
	}
	if len(jobs) == 0 {
		return failedReport(task.CheckID, "no gfw check targets")
	}

	jobCh := make(chan targetJob)
	outCh := make(chan targetOutput, len(jobs))
	workers := min(task.Parallel, len(jobs))

	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for job := range jobCh {
				outCh <- targetOutput{
					operator: job.operator,
					result:   pingTarget(ctx, job.target, task.PingCount, task.TimeoutSeconds),
				}
			}
		}()
	}

	go func() {
		defer close(jobCh)
		for _, job := range jobs {
			select {
			case <-ctx.Done():
				return
			case jobCh <- job:
			}
		}
	}()

	go func() {
		wg.Wait()
		close(outCh)
	}()

	operators := map[string]OperatorResult{}
	for output := range outCh {
		item := operators[output.operator]
		item.Targets = append(item.Targets, output.result)
		operators[output.operator] = item
	}

	if len(operators) == 0 && ctx.Err() != nil {
		return failedReport(task.CheckID, ctx.Err().Error())
	}

	summary := summarize(operators)
	status := classify(operators, summary)
	summary.Status = status

	return Report{
		CheckID:         task.CheckID,
		Status:          status,
		Summary:         summary,
		OperatorSummary: operators,
		RawResult: map[string]any{
			"operators": operators,
			"summary":   summary,
		},
	}
}

func normalizeTask(task Task) Task {
	if len(task.Targets) == 0 {
		task.Targets = DefaultTargets()
	}
	if task.PingCount <= 0 {
		task.PingCount = 2
	}
	if task.TimeoutSeconds <= 0 {
		task.TimeoutSeconds = 2
	}
	if task.Parallel <= 0 {
		task.Parallel = 12
	}
	return task
}

func pingTarget(parent context.Context, target Target, count int, timeoutSeconds int) TargetResult {
	timeout := time.Duration(count*timeoutSeconds+2) * time.Second
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()

	args := pingArgs(target.Host, count, timeoutSeconds)
	cmd := exec.CommandContext(ctx, "ping", args...)
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output

	err := cmd.Run()
	latency := parseAverageLatency(output.String())
	if err == nil || latency > 0 {
		return TargetResult{Name: target.Name, Host: target.Host, Status: "ok", LatencyMS: latency}
	}

	message := "timeout"
	if err != nil && !errors.Is(ctx.Err(), context.DeadlineExceeded) {
		message = err.Error()
	}
	return TargetResult{Name: target.Name, Host: target.Host, Status: "timeout", Error: message}
}

func pingArgs(host string, count int, timeoutSeconds int) []string {
	if runtime.GOOS == "windows" {
		return []string{"-n", strconv.Itoa(count), "-w", strconv.Itoa(timeoutSeconds * 1000), host}
	}
	return []string{"-n", "-c", strconv.Itoa(count), "-W", strconv.Itoa(timeoutSeconds), "-q", host}
}

func parseAverageLatency(output string) float64 {
	for _, item := range latencyPatterns {
		match := item.re.FindStringSubmatch(output)
		if len(match) <= item.group {
			continue
		}
		value, err := strconv.ParseFloat(match[item.group], 64)
		if err == nil {
			return value
		}
	}
	return 0
}

func summarize(operators map[string]OperatorResult) Summary {
	summary := Summary{}
	for operator, result := range operators {
		result = summarizeOperator(result)
		operators[operator] = result
		summary.Total += result.Total
		summary.Success += result.Success
		summary.Timeout += result.Timeout
	}
	if summary.Total > 0 {
		summary.TimeoutRatio = float64(summary.Timeout) / float64(summary.Total)
	}
	return summary
}

func summarizeOperator(result OperatorResult) OperatorResult {
	result.Total = len(result.Targets)
	result.Success = 0
	result.Timeout = 0
	var sum float64
	for _, target := range result.Targets {
		if target.Status != "ok" {
			result.Timeout++
			continue
		}
		result.Success++
		sum += target.LatencyMS
		if result.MinMS == 0 || target.LatencyMS < result.MinMS {
			result.MinMS = target.LatencyMS
		}
		if target.LatencyMS > result.MaxMS {
			result.MaxMS = target.LatencyMS
			result.Slowest = target.Name
		}
	}
	if result.Success > 0 {
		result.AverageMS = sum / float64(result.Success)
	}
	return result
}

func classify(operators map[string]OperatorResult, summary Summary) string {
	if summary.Total <= 0 {
		return StatusFailed
	}
	if summary.Success == 0 || summary.TimeoutRatio >= 0.95 {
		return StatusBlocked
	}

	reachableOperators := 0
	for _, result := range operators {
		if result.Success > 0 {
			reachableOperators++
		}
	}
	if reachableOperators >= 3 && summary.TimeoutRatio <= 0.8 {
		return StatusNormal
	}
	return StatusPartial
}

func failedReport(checkID int64, message string) Report {
	return Report{
		CheckID:      checkID,
		Status:       StatusFailed,
		Summary:      Summary{Status: StatusFailed},
		RawResult:    map[string]any{},
		ErrorMessage: fmt.Sprintf("gfw check failed: %s", message),
	}
}
