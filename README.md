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
