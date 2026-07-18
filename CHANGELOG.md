# Changelog

## 0.4.0

- Require Julia 1.10 or newer.
- Add explicit scheduler-managed `start(runner)` and sticky
  `start_on_thread(runner, id)` execution modes.
- Add opt-in Linux CPU affinity with
  `start_on_thread(runner, id; cpuid=...)` through a ThreadPinning.jl package
  extension.
- Guarantee GC/scheduler progress in runner loops, including single-threaded
  Julia, without injecting exceptions into running tasks.
- Make runner shutdown cooperative, race-safe, observable, and diagnosable;
  fatal task and cleanup failures now propagate through `wait` and `close`.
- Resume static and dynamic composites after the sub-agent that threw, matching
  Agrona's cursor semantics.
- Use atomic publication for dynamic-composite requests, controllable idle
  modes, and error counters.
- Add checked and unchecked `AgentInvoker` APIs and expected termination
  semantics.
- Remove the runtime Hwloc dependency and distinguish Julia task assignment
  from optional OS CPU pinning.
- Add Aqua QA, focused benchmark infrastructure, an Apache-2.0 license, and
  Agrona attribution.
- Document the busy-spin placement contract and add reproducible runner-mode
  benchmark smoke coverage without timing gates.
