# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

const RUNNER_SAFEPOINT_INTERVAL = 1024
@assert ispow2(RUNNER_SAFEPOINT_INTERVAL)

@enum AgentRunnerState::UInt8 begin
    AGENT_RUNNER_INIT
    AGENT_RUNNER_STARTING
    AGENT_RUNNER_STARTED
    AGENT_RUNNER_RUNNING
    AGENT_RUNNER_CLOSING
    AGENT_RUNNER_CLOSED
end

abstract type RunnerExecutionMode end
struct SchedulerManagedExecution <: RunnerExecutionMode end
struct ThreadAssignedExecution{COOPERATIVE} <: RunnerExecutionMode end

@inline managed_thread_count() = Threads.nthreads(:interactive) + Threads.nthreads(:default)

function pin_assigned_thread!(threadid::Int, cpuid::Int)
    extension = Base.get_extension(@__MODULE__, :AgentThreadPinningExt)
    extension === nothing && throw(
        ArgumentError(
            "CPU pinning requires ThreadPinning.jl; install and load ThreadPinning before " *
            "calling start_on_thread with cpuid",
        ),
    )
    return extension.pin_assigned_thread!(threadid, cpuid)
end

"""
    AgentRunner(idle_strategy, agent; error_handler=nothing, error_counter=nothing)

Run one agent duty cycle repeatedly in a Julia `Task`. A runner can be started
only once. Use `start(runner)` for scheduler-cooperative execution or
`start_on_thread(runner, threadid)` to assign the task to one Julia runtime
thread.

`error_counter`, when supplied, must be a `Threads.Atomic{<:Integer}`. It counts
errors thrown by `do_work`; lifecycle and termination errors are reported but
do not increment the counter.
"""
mutable struct AgentRunner{I<:IdleStrategy,A,H,C}
    idle_strategy::I
    agent::A
    error_handler::H
    error_counter::C
    @atomic is_started::Bool
    @atomic state::AgentRunnerState
    task::Union{StableTasks.StableTask,Nothing}
    lifecycle_lock::ReentrantLock

    function AgentRunner(idle_strategy::I, agent::A; error_handler=nothing, error_counter=nothing) where {I,A}
        validate_error_counter(error_counter)
        new{I,A,typeof(error_handler),typeof(error_counter)}(
            idle_strategy,
            agent,
            error_handler,
            error_counter,
            false,
            AGENT_RUNNER_INIT,
            nothing,
            ReentrantLock(),
        )
    end
end

@inline runner_state(runner::AgentRunner) = @atomic :acquire runner.state
@inline set_runner_state!(runner::AgentRunner, state::AgentRunnerState) =
    @atomic :release runner.state = state

"""
    start(runner::AgentRunner)

Start a migratable task in Julia's default thread pool. This mode reaches a GC
safepoint and yields after each duty cycle, so it remains cooperative when
Julia is launched with a single thread.
"""
start(runner::AgentRunner) =
    start_runner(runner, SchedulerManagedExecution(), nothing, nothing)

"""
    start_on_thread(runner::AgentRunner, threadid::Integer; cpuid=nothing)

Start a sticky task assigned to the given interactive or default Julia runtime
thread. With `cpuid`, the optional ThreadPinning.jl extension first pins that
runtime thread to the given physical OS CPU ID. Load ThreadPinning.jl before
using this keyword. CPU pinning is supported on Linux and does not establish
scheduling priority.

When the target pool has one managed Julia thread, the task yields after every
duty cycle. In a multi-thread target pool, it retains dedicated-loop behavior
and explicitly polls a GC safepoint every `RUNNER_SAFEPOINT_INTERVAL` duty
cycles.
"""
function start_on_thread(
    runner::AgentRunner,
    threadid::Integer;
    cpuid::Union{Nothing,Integer}=nothing,
)
    id = Int(threadid)
    is_managed_thread_id(id) || throw(
        ArgumentError("threadid must identify an interactive or default Julia runtime thread"),
    )
    pool = Threads.threadpool(id)
    mode = if Threads.nthreads(pool) == 1
        ThreadAssignedExecution{true}()
    else
        ThreadAssignedExecution{false}()
    end
    cpu = cpuid === nothing ? nothing : Int(cpuid)
    return start_runner(runner, mode, id, cpu)
end

"""
    start_on_thread(runner::AgentRunner)

Compatibility alias for `start(runner)`. It does not assign the task to a
specific thread; use the two-argument method for sticky placement.
"""
start_on_thread(runner::AgentRunner) = start(runner)

function is_managed_thread_id(threadid::Int)
    1 <= threadid <= Threads.maxthreadid() || return false
    pool = Threads.threadpool(threadid)
    return pool === :interactive || pool === :default
end

function start_runner(
    runner::AgentRunner,
    mode::RunnerExecutionMode,
    threadid::Union{Nothing,Int},
    cpuid::Union{Nothing,Int},
)
    lock(runner.lifecycle_lock)
    try
        state = runner_state(runner)
        if state === AGENT_RUNNER_CLOSED || state === AGENT_RUNNER_CLOSING
            throw(ArgumentError("AgentRunner is closed"))
        elseif state !== AGENT_RUNNER_INIT
            throw(ArgumentError("AgentRunner is already started"))
        end

        try
            cpuid === nothing || pin_assigned_thread!(something(threadid), cpuid)
            @atomic :release runner.is_started = true
            set_runner_state!(runner, AGENT_RUNNER_STARTING)

            task = if threadid === nothing
                StableTasks.@spawn run(runner, mode)
            else
                StableTasks.@spawnat threadid run(runner, mode)
            end
            runner.task = task
            set_runner_state!(runner, AGENT_RUNNER_STARTED)
            return task
        catch
            @atomic :release runner.is_started = false
            set_runner_state!(runner, AGENT_RUNNER_INIT)
            rethrow()
        end
    finally
        unlock(runner.lifecycle_lock)
    end
end

"""
    close(runner::AgentRunner, retry_wait=0.1; on_stall=nothing)

Request cooperative shutdown and wait for the runner task and `on_close` to
finish. `do_work` must return periodically and application code must wake any
blocking operation during shutdown; this package never injects an exception
into an already-running task.

If the task remains live for `retry_wait` seconds, `on_stall(runner)` is called
before waiting again. Use `runner_task(runner)` inside the callback for task
diagnostics. A `retry_wait` of zero waits indefinitely without callbacks.
"""
function Base.close(
    runner::AgentRunner,
    retry_wait::Real=0.1;
    on_stall=nothing,
)
    retry_wait >= 0 || throw(ArgumentError("retry_wait must be non-negative"))

    task = nothing
    close_owner = false

    lock(runner.lifecycle_lock)
    try
        while true
            state = runner_state(runner)

            if state === AGENT_RUNNER_CLOSED
                return nothing
            elseif state === AGENT_RUNNER_INIT
                set_runner_state!(runner, AGENT_RUNNER_CLOSING)
                close_owner = true
                break
            elseif state === AGENT_RUNNER_STARTED
                _, success = @atomicreplace runner.state AGENT_RUNNER_STARTED => AGENT_RUNNER_CLOSING
                if success
                    task = runner.task
                    break
                end
            elseif state === AGENT_RUNNER_RUNNING
                _, success = @atomicreplace runner.state AGENT_RUNNER_RUNNING => AGENT_RUNNER_CLOSING
                if success
                    task = runner.task
                    break
                end
            elseif state === AGENT_RUNNER_STARTING
                # The task is published while this lock is held, so callers do
                # not normally observe this state. Retry defensively.
                yield()
            else
                task = runner.task
                break
            end
        end
    finally
        unlock(runner.lifecycle_lock)
    end

    if close_owner
        try
            close_agent(runner)
        finally
            set_runner_state!(runner, AGENT_RUNNER_CLOSED)
        end
    elseif task === nothing
        wait_for_close(runner, retry_wait; on_stall)
    else
        wait_for_task(runner, task, retry_wait; on_stall)
        wait_for_close(runner, retry_wait; on_stall)
    end

    return nothing
end

"""
    request_stop!(runner::AgentRunner)

Request non-blocking cooperative shutdown of a started runner. The runner task
owns `on_close` and the final transition to closed. Returns `true` when this
call initiated shutdown and `false` if no transition was needed.
"""
function request_stop!(runner::AgentRunner)
    while true
        state = runner_state(runner)
        if state === AGENT_RUNNER_STARTED
            _, success = @atomicreplace runner.state AGENT_RUNNER_STARTED => AGENT_RUNNER_CLOSING
            success && return true
        elseif state === AGENT_RUNNER_RUNNING
            _, success = @atomicreplace runner.state AGENT_RUNNER_RUNNING => AGENT_RUNNER_CLOSING
            success && return true
        else
            return false
        end
    end
end

"""
    is_started(runner::AgentRunner)

Return whether the runner successfully began starting.
"""
is_started(runner::AgentRunner) = @atomic :acquire runner.is_started

"""
    is_closed(runner::AgentRunner)

Return whether runner cleanup has finished.
"""
is_closed(runner::AgentRunner) = runner_state(runner) === AGENT_RUNNER_CLOSED
Base.isopen(runner::AgentRunner) = !is_closed(runner)

"""
    is_running(runner::AgentRunner)

Return whether the runner is executing agent duty cycles.
"""
is_running(runner::AgentRunner) = runner_state(runner) === AGENT_RUNNER_RUNNING

"""
    agent(runner::AgentRunner)

Return the agent owned by this runner.
"""
agent(runner::AgentRunner) = runner.agent

"""
    runner_task(runner::AgentRunner)

Return the runner's task, or `nothing` before it is started.
"""
function runner_task(runner::AgentRunner)
    lock(runner.lifecycle_lock)
    try
        return runner.task
    finally
        unlock(runner.lifecycle_lock)
    end
end

function wait_for_task(
    runner::AgentRunner,
    task::StableTasks.StableTask,
    retry_wait::Real;
    on_stall,
)
    if retry_wait == 0
        fetch(task)
        return nothing
    end

    while !istaskdone(task)
        result = timedwait(
            () -> istaskdone(task),
            retry_wait;
            pollint=poll_interval(retry_wait),
        )
        if result === :timed_out && !istaskdone(task) && on_stall !== nothing
            on_stall(runner)
        end
    end

    fetch(task)
    return nothing
end

function wait_for_close(runner::AgentRunner, retry_wait::Real; on_stall)
    if retry_wait == 0
        while !is_closed(runner)
            yield()
        end
        return nothing
    end

    while !is_closed(runner)
        result = timedwait(
            () -> is_closed(runner),
            retry_wait;
            pollint=poll_interval(retry_wait),
        )
        if result === :timed_out && !is_closed(runner) && on_stall !== nothing
            on_stall(runner)
        end
    end
    return nothing
end

@inline poll_interval(retry_wait::Real) = min(max(retry_wait / 10, 0.001), 0.01)

"""
    wait(runner::AgentRunner)

Wait for the runner to finish. Fatal runner-task failures, including failures
from error reporting or cleanup, are propagated as `TaskFailedException`.
"""
function Base.wait(runner::AgentRunner)
    task = runner_task(runner)
    if task === nothing
        runner_state(runner) === AGENT_RUNNER_CLOSING &&
            wait_for_close(runner, 0; on_stall=nothing)
        return nothing
    end

    fetch(task)
    wait_for_close(runner, 0; on_stall=nothing)
    return nothing
end

function run(runner::AgentRunner, mode::RunnerExecutionMode)
    while runner_state(runner) === AGENT_RUNNER_STARTING
        yield()
    end

    _, claimed = @atomicreplace runner.state AGENT_RUNNER_STARTED => AGENT_RUNNER_RUNNING
    if !claimed
        if runner_state(runner) === AGENT_RUNNER_CLOSING
            try
                close_agent(runner)
            finally
                set_runner_state!(runner, AGENT_RUNNER_CLOSED)
            end
        end
        return nothing
    end

    try
        try
            on_start(runner.agent)
        catch e
            request_stop!(runner)
            report_error(runner.error_handler, runner.agent, e)
        end

        run_loop(runner, mode)
    finally
        try
            close_agent(runner)
        finally
            set_runner_state!(runner, AGENT_RUNNER_CLOSED)
        end
    end
    return nothing
end

function close_agent(runner::AgentRunner)
    try
        on_close(runner.agent)
    catch e
        report_error(runner.error_handler, runner.agent, e)
    end
    return nothing
end

@inline function run_loop(runner::AgentRunner, mode::RunnerExecutionMode)
    iterations = 0
    while is_running(runner)
        try
            idle(runner.idle_strategy, do_work(runner.agent))
        catch e
            handle_runner_error(runner, e)
        end

        iterations += 1
        runner_checkpoint(mode, iterations)
    end
    return nothing
end

@inline function runner_checkpoint(::SchedulerManagedExecution, ::Int)
    GC.safepoint()
    yield()
    return nothing
end

@inline function runner_checkpoint(::ThreadAssignedExecution{true}, ::Int)
    GC.safepoint()
    yield()
    return nothing
end

@inline function runner_checkpoint(::ThreadAssignedExecution{false}, iterations::Int)
    if (iterations & (RUNNER_SAFEPOINT_INTERVAL - 1)) == 0
        GC.safepoint()
    end
    return nothing
end

@noinline function handle_runner_error(runner::AgentRunner, e)
    if e isa InterruptException
        request_stop!(runner)
    elseif e isa AgentTerminationException
        request_stop!(runner)
        is_expected(e) || report_error(runner.error_handler, runner.agent, e)
    else
        try
            handle_error(runner.error_handler, runner.error_counter, runner.agent, e)
        catch on_error_e
            if on_error_e isa AgentTerminationException
                request_stop!(runner)
            else
                rethrow(on_error_e)
            end
        end
    end
    return nothing
end

Base.isready(runner::AgentRunner) = is_closed(runner)

export AgentRunner,
    agent,
    is_closed,
    is_running,
    is_started,
    request_stop!,
    runner_task,
    start,
    start_on_thread
