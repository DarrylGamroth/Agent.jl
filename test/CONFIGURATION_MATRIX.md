# AgentRunner runtime configuration matrix

| Area | Axis | Permutations | Evidence | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Compatibility | Julia version | declared minimum, current stable, nightly | `Project.toml` compat and CI `min`/`1`/`nightly` matrix | Covered | `min` resolves the Julia 1.10 compatibility floor; earlier Julia versions are intentionally unsupported. |
| Quality | Aqua QA | ambiguities, exports, type parameters, dependencies, compat, piracy, persistent tasks | `Aqua.test_all(Agent)` in `test/runtests.jl` | Covered | Runs as part of the normal package test target. |
| Run loop | Managed Julia threads | `--threads=1` | `AgentRunner Thread-Count Specialization`; CI `threads: '1'` | Covered | Exercises the periodic safepoint specialization. |
| Run loop | Managed Julia threads | `--threads=4` | Full runner and integration suites; CI `threads: '4'` | Covered | Exercises the generic multi-thread run loop. |
| Placement | Thread pools | `--threads=2,1` | `AgentRunner Thread Assignment`; CI `threads: '2,1'` | Covered | Validates ids spanning interactive and default pools and rejects the foreign range. |
| Lifecycle | Start/close ordering | close before start, task before close, concurrent close/start | `AgentRunner Close Before Start`, `Interrupt Handling`, and `Close Wins Startup Race` | Covered | Verifies single cleanup ownership. |
| Failure | Task and cleanup result | normal, fatal work error, cleanup error | `Fatal Failure Propagation` and `Cleanup Failure Closes Runner` | Covered | Verifies task failure propagation and the closed invariant. |
