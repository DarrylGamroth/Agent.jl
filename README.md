# Agent.jl

[![Build Status](https://github.com/DarrylGamroth/Agent.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DarrylGamroth/Agent.jl/actions/workflows/ci.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/DarrylGamroth/Agent.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/Agent.jl)

A Julia implementation of the Agent pattern from [Agrona](https://github.com/aeron-io/agrona), providing high-performance background workers that run on separate threads with configurable idle strategies.

## Usage

```julia
using Agent

# 1. Define your agent
mutable struct MyAgent
    counter::Int
end

# 2. Implement the required methods
function Agent.do_work(agent::MyAgent)
    agent.counter += 1
    println("Working... count: $(agent.counter)")
    
    # Agent can terminate itself by throwing AgentTerminationException
    if agent.counter >= 10
        throw(AgentTerminationException())
    end
    
    return 1  # Return work count (>0 indicates work was done)
end

Agent.name(agent::MyAgent) = "Counter"
Agent.on_start(agent::MyAgent) = println("Agent starting...")
Agent.on_close(agent::MyAgent) = println("Agent closing...")
Agent.on_error(agent::MyAgent, e) = println("Agent error: $e")

# 3. Run the agent
agent = MyAgent(0)
runner = AgentRunner(BackoffIdleStrategy(), agent)
start_on_thread(runner)
wait(runner)  # Will stop after 10 iterations or press Ctrl+C
close(runner)
```

## Idle Strategies

Choose based on your latency vs CPU usage requirements:

- `BackoffIdleStrategy()` - Progressive backoff (recommended default)
- `BusySpinIdleStrategy()` - Lowest latency, highest CPU usage  
- `YieldingIdleStrategy()` - Cooperative multitasking
- `SleepingIdleStrategy()` - Sleeps for a defined amount of time when idle
- `NoOpIdleStrategy()` - No-op when idle
- `SleepingMillisIdleStrategy()` - Sleeps for a defined amount of time in milliseconds
- `ControllableIdleStrategy(status_ref)` - Switches behavior based on `status_ref::Ref{ControllableIdleMode}`

Idle strategies also expose `Agent.alias(strategy)` for a short, stable name.

## Advanced Features

**Thread Pinning:**
```julia
# Run on a specific thread (useful for NUMA optimization or isolation)
start_on_thread(runner, 2)  # Run on thread 2

# Or let Julia's scheduler choose the thread
start_on_thread(runner)      # Automatic thread assignment

# Check available threads
println("Available threads: ", Threads.nthreads())
println("Current thread: ", Threads.threadid())
```

Thread pinning is beneficial for:
- **NUMA systems**: Pin agents to threads on specific CPU sockets
- **Real-time workloads**: Isolate critical agents from general computation
- **Cache optimization**: Keep related agents on the same physical core

**AgentInvoker:**
```julia
# Drive an agent without creating a Task
agent = MyAgent(0)
invoker = AgentInvoker(agent)
start(invoker)
try
    while is_running(invoker)
        Agent.invoke(invoker)
    end
catch e
    Agent.handle_error(invoker, e)
end
close(invoker)
```

**Composite Agents:**
```julia
agent_a = MyAgent(0)
agent_b = MyAgent(0)
composite = CompositeAgent(agent_a, agent_b)
runner = AgentRunner(NoOpIdleStrategy(), composite)
start_on_thread(runner)
```
For best performance, construct `CompositeAgent` directly from concrete agent values (as above) rather than from
type-erased containers like `Vector{Any}` or `Vector{AbstractAgent}`.

**Dynamic Composite Agents:**
```julia
dyn = DynamicCompositeAgent("dynamic", agent_a)
Agent.on_start(dyn)
try_add(dyn, agent_b)
Agent.do_work(dyn) # processes pending add/remove requests
Agent.on_close(dyn)
```

Status values are `Agent.INIT`, `Agent.ACTIVE`, and `Agent.CLOSED`. Calls to `try_add`/`try_remove` are only valid in
the `Agent.ACTIVE` state.

**Controllable Idle Strategy:**
```julia
status = Ref{ControllableIdleMode}(CONTROLLABLE_NOOP)
strategy = ControllableIdleStrategy(status)
status[] = CONTROLLABLE_YIELD
```
This uses a `Ref` so the mode can be adjusted externally (e.g., from another task) without mutating the strategy itself,
which mirrors Agrona's "indicator" model and keeps control separate from behavior.

**Error Handling:**
```julia
errors = Ref(0)
handler = (agent, err) -> @warn "agent error" agent=Agent.name(agent) error=err

runner = AgentRunner(BackoffIdleStrategy(), agent; error_handler=handler, error_counter=errors)
start_on_thread(runner)
wait(runner)
close(runner)
```

## Agent Interface

Implement these methods for your agent type:

```julia
function Agent.do_work(agent)     # Main work method - return work count (>0 = work done)
Agent.name(agent)                 # Agent identifier string
Agent.on_start(agent)             # Called when agent starts
Agent.on_close(agent)             # Called when agent stops  
Agent.on_error(agent, e)          # Called when exception occurs
```

**Note:** An agent can terminate itself by throwing `AgentTerminationException()` from any method.
