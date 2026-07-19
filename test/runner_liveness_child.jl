# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0

using Agent

struct LivenessAgent
    started::Channel{Nothing}
end

Agent.name(::LivenessAgent) = "liveness"
Agent.on_start(agent::LivenessAgent) = put!(agent.started, nothing)
Agent.do_work(::LivenessAgent) = 0

function exercise(strategy, start_runner)
    owned_agent = LivenessAgent(Channel{Nothing}(1))
    runner = AgentRunner(strategy, owned_agent)
    start_runner(runner)
    take!(owned_agent.started)
    return runner
end

strategies() = (
    NoOpIdleStrategy(),
    BusySpinIdleStrategy(),
    BackoffIdleStrategy(),
    SleepingIdleStrategy(),
)

mode = only(ARGS)
if mode == "single"
    Agent.managed_thread_count() == 1 || error("single mode requires one managed thread")
    for strategy in strategies()
        runner = exercise(strategy, start)
        close(runner)

        assigned_runner = exercise(strategy, runner -> start_on_thread(runner, 1))
        close(assigned_runner)
    end
elseif mode == "gc"
    Agent.managed_thread_count() > 1 || error("gc mode requires multiple managed threads")
    target_thread = Agent.managed_thread_count()
    for strategy in strategies()
        runner = exercise(strategy, runner -> start_on_thread(runner, target_thread))
        GC.gc()
        close(runner)
    end

    # A multi-pool Julia process can still contain a one-thread pool. An
    # assigned runner in that pool must cooperate so its caller can resume.
    for threadid in 1:Agent.managed_thread_count()
        pool = Threads.threadpool(threadid)
        if Threads.nthreads(pool) == 1
            runner = exercise(NoOpIdleStrategy(), runner -> start_on_thread(runner, threadid))
            close(runner)
        end
    end
else
    error("unknown liveness mode: $mode")
end

println("runner liveness: ok")
