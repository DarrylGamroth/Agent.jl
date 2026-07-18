# Agent.jl

[![CI](https://github.com/DarrylGamroth/Agent.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DarrylGamroth/Agent.jl/actions/workflows/ci.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/DarrylGamroth/Agent.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/Agent.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Agent.jl is a Julia 1.10+ implementation of the
[Agrona](https://github.com/aeron-io/agrona) Agent protocol: duty-cycle agents,
runners, invokers, composite agents, and idle strategies.

The package intentionally stops at the Agent abstraction. Other Agrona
facilities—buffers, queues, clocks, counters, codecs, and collections—belong in
separate packages.

## Quick start

```julia
using Agent

mutable struct CounterAgent
    count::Int
end

function Agent.do_work(agent::CounterAgent)
    agent.count += 1
    agent.count == 10 && throw(AgentTerminationException())
    return 1
end

Agent.name(::CounterAgent) = "counter"
Agent.on_start(::CounterAgent) = nothing
Agent.on_close(::CounterAgent) = nothing

runner = AgentRunner(BackoffIdleStrategy(), CounterAgent(0))
start(runner)
wait(runner)
close(runner) # idempotent after wait
```

`AgentTerminationException()` is an expected, quiet termination for backward
compatibility. Use `AgentTerminationException(false)` or
`AgentTerminationException("reason"; expected=false)` when the termination
should also be reported as an error.

## Execution and Julia threads

AgentRunner has two explicit execution modes:

```julia
start(runner)                 # migratable, scheduler-cooperative task
start_on_thread(runner, 2)    # sticky task on Julia runtime thread 2
```

`start_on_thread` assigns a Julia task to a runtime thread. Valid IDs belong to
Julia's `:interactive` or `:default` thread pool; `:foreign` thread IDs are
rejected. Assignment alone does not set OS affinity, but the optional
[ThreadPinning.jl](https://github.com/carstenbauer/ThreadPinning.jl) extension
can pin the selected Julia runtime thread to a CPU on Linux:

```julia
using Agent, ThreadPinning

cpu = first(ThreadPinning.cpuids()) # physical OS CPU IDs start at zero
start_on_thread(runner, 2; cpuid=cpu)
```

This combines sticky task placement with actual OS CPU affinity. It is the
Julia analogue of passing Agrona `AgentRunner.startOnThread` an
affinity-aware `ThreadFactory`. Pinning does not reserve the core or change OS
scheduling priority. Affinity belongs to the Julia runtime thread, persists
after the runner closes, and affects later tasks assigned to that thread; use
ThreadPinning.jl to restore or remove it when appropriate. On a one-thread
Julia process, use thread ID `1`; the runner still yields after each duty cycle
for scheduler and GC progress.

The no-argument `start_on_thread(runner)` remains as a compatibility alias for
`start(runner)`, but it does not provide thread assignment.

### Safepoints

Agrona's
[`IdleStrategy` documentation](https://github.com/aeron-io/agrona/blob/master/agrona/src/main/java/org/agrona/concurrent/IdleStrategy.java)
warns that a counted JVM loop using an inlined no-op or busy-spin strategy may
delay time-to-safepoint. Agrona leaves the poll to the JVM and suggests
preventing the idle method from being inlined, for example with
`-XX:CompileCommand=dontinline,org.agrona.concurrent.NoOpIdleStrategy::idle`;
`AgentRunner` itself does not add a poll.

Julia does not have an equivalent reliable per-method JIT switch, so Agent.jl
makes the execution mode responsible for progress:

- `start(runner)` calls `GC.safepoint()` and yields after every duty cycle.
- An explicitly assigned runner does the same when its Julia thread pool has
  one managed thread, allowing GC and the task requesting shutdown to run.
- With multiple managed threads, an explicitly assigned runner preserves its
  dedicated-loop behavior and calls `GC.safepoint()` every 1024 duty cycles.

Custom loops that call `idle` directly must provide their own safepoint or
scheduler-yield policy.

## Cooperative shutdown

```julia
request_stop!(runner) # non-blocking request
wait(runner)          # wait and propagate fatal task failures

close(runner, 0.25; on_stall = runner -> begin
    @warn "agent has not stopped" agent=Agent.name(agent(runner)) task=runner_task(runner)
end)
```

`close` requests shutdown, waits for the current duty cycle, and waits for
`on_close`. `do_work` must return periodically. If it blocks, application code
must arrange to wake that operation. Agent.jl never injects an exception into
an already-running task.

The optional `on_stall` callback runs after each close timeout and can inspect
the runner and its task. A retry interval of zero waits indefinitely and does
not call the callback.

## Idle strategies

- `BackoffIdleStrategy()` progressively spins, yields, then parks.
- `BusySpinIdleStrategy()` issues a CPU pause hint.
- `YieldingIdleStrategy()` yields when no work was done.
- `SleepingIdleStrategy([nanoseconds])` parks, defaulting to 1 microsecond.
- `SleepingMillisIdleStrategy([milliseconds])` sleeps, defaulting to 1 ms.
- `NoOpIdleStrategy()` performs no idle operation.
- `ControllableIdleStrategy([mode])` uses an atomically published mode.

Stateful idle strategies are owned by one runner and must not be shared by
concurrently executing runners.

`BusySpinIdleStrategy` is only a pause instruction; it does not choose where
the runner executes. With `start(runner)`, or with an assigned one-thread pool,
the runner still yields each duty cycle and is therefore cooperative rather
than a dedicated busy spin. For dedicated-loop behavior, assign the runner to
a Julia runtime thread in a pool containing more than one managed thread. Add
`cpuid` when Linux CPU affinity is required. Neither mode reserves a core or
changes OS scheduling priority.

```julia
strategy = ControllableIdleStrategy(CONTROLLABLE_NOOP)
set_idle_mode!(strategy, CONTROLLABLE_YIELD)
@assert idle_mode(strategy) == CONTROLLABLE_YIELD
```

The available controllable modes are `CONTROLLABLE_NOT_CONTROLLED`,
`CONTROLLABLE_NOOP`, `CONTROLLABLE_BUSY_SPIN`, `CONTROLLABLE_YIELD`, and
`CONTROLLABLE_PARK`.

## AgentInvoker

`AgentInvoker` lets a caller own the loop. `invoke` is the checked,
Agrona-compatible API:

```julia
invoker = AgentInvoker(CounterAgent(0))
start(invoker)
while is_running(invoker)
    Agent.invoke(invoker)
end
close(invoker)
```

`invoke_unchecked` omits the catch path for a loop that centralises exception
handling itself:

```julia
try
    while is_running(invoker)
        invoke_unchecked(invoker)
    end
catch exception
    handle_error(invoker, exception)
end
```

The invoker is not thread-safe.

## Composite agents

`CompositeAgent` stores a concrete tuple, allowing heterogeneous agents to be
scheduled as one unit without type erasure:

```julia
agent_a = CounterAgent(0)
agent_b = CounterAgent(0)
composite = CompositeAgent(agent_a, agent_b)
runner = AgentRunner(NoOpIdleStrategy(), composite)
start(runner)
```

If a sub-agent throws during `do_work`, the next invocation resumes at the
following agent before wrapping to the first. This follows Agrona's cursor
protocol and prevents a repeatedly failing early agent from starving later
agents.

`DynamicCompositeAgent` accepts one pending add and one pending identity-based
remove request from other threads:

```julia
composite = DynamicCompositeAgent("dynamic", agent_a)
Agent.on_start(composite)
try_add(composite, agent_b)
Agent.do_work(composite) # consumes pending requests on the owner thread
Agent.on_close(composite)
```

Add/remove publication is atomic and non-blocking. Agent lifecycle methods are
still executed only by the composite's owner.

## Error handling

An optional external handler runs before `Agent.on_error`. Only exceptions from
`do_work` increment the optional counter; startup, cleanup, and termination
errors are reported without incrementing it.

```julia
errors = Threads.Atomic{Int}(0)
handler = (owned_agent, exception) ->
    @warn "agent error" agent=Agent.name(owned_agent) exception
owned_agent = CounterAgent(0)

runner = AgentRunner(
    BackoffIdleStrategy(),
    owned_agent;
    error_handler=handler,
    error_counter=errors,
)
```

The counter must be `Threads.Atomic{<:Integer}` because runner errors can be
observed and counted across Julia threads. An ordinary `Ref` is rejected.

## Benchmarks

The `benchmark/` environment contains focused, closed-loop microbenchmarks for
the invoker, composites, idle primitives, and runner placement modes. They
report the source revision, Julia environment, host, and thread configuration,
and make no cross-machine latency guarantee. See
[`benchmark/README.md`](benchmark/README.md) for the reproducible setup and the
scope of the measurements.

## License

Copyright 2024–2026 Rubus Technologies Inc. Licensed under the
[Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for Agrona
attribution.
