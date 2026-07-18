# AgentRunner runtime configuration matrix

| Area | Axis | Permutations | Evidence | Status |
| --- | --- | --- | --- | --- |
| Compatibility | Julia version | 1.10 minimum, current stable, nightly | `Project.toml`; CI `min`/`1`/`nightly` | Covered |
| Quality | Package QA | Aqua ambiguities, dependencies, compat, piracy, stale deps, persistent tasks | `Aqua.test_all(Agent)` | Covered |
| Scheduling | Scheduler-managed | migratable task | `Scheduler-Managed Lifecycle` | Covered |
| Scheduling | Explicit placement | default and interactive pool IDs; foreign/out-of-range IDs | `Explicit Julia Thread Assignment`; CI `--threads=2,1` | Covered |
| Scheduling | Busy-spin placement contract | scheduler-managed, assigned one-thread pool, assigned multi-thread pool | isolated liveness tests; `benchmark/runnerbenchmarks.jl`; API and README documentation | Covered |
| Placement | OS CPU affinity | Linux one-/multi-thread pin and restore; unsupported OS | `test_thread_pinning.jl`; Linux and cross-platform CI | Covered |
| Liveness | One managed thread | cooperative close with no-op, busy-spin, backoff, and nanosecond-sleep strategies | isolated `runner_liveness_child.jl single`; CI `--threads=1` | Covered |
| Liveness | Multiple managed threads | stop-the-world `GC.gc()` while an explicitly assigned runner uses each non-polling strategy | isolated `runner_liveness_child.jl gc`; CI `--threads=4` and `--threads=2,1` | Covered |
| Lifecycle | Start/close ordering | close before start, close before task claim, concurrent close, non-blocking stop | `test_agentrunner.jl` lifecycle testsets | Covered |
| Failure | Work, startup, cleanup | handled work error, fatal work error, startup error, cleanup error, expected/unexpected termination | runner and invoker failure testsets | Covered |
| Fairness | Composite cursor | static and dynamic failure before later agent | `Work Cursor Resumes After Failure` | Covered |
| Publication | Cross-task control | controllable idle mode, dynamic add request, atomic error counter | idle and dynamic composite testsets | Covered |

The liveness cases run in subprocesses with a hard parent-side timeout so a
regression in a non-safepointing loop fails CI instead of hanging the test job.
