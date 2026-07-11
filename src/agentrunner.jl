"""
Agent runner containing an `Agent` which is run on a `Task`.
Note: An instance can only be started once then discarded.
"""
const SINGLE_THREAD_SAFEPOINT_INTERVAL = 1024
@assert ispow2(SINGLE_THREAD_SAFEPOINT_INTERVAL)

@enum AgentRunnerState::UInt8 begin
    AGENT_RUNNER_INIT
    AGENT_RUNNER_STARTING
    AGENT_RUNNER_STARTED
    AGENT_RUNNER_RUNNING
    AGENT_RUNNER_CLOSING
    AGENT_RUNNER_CLOSED
end

@inline managed_thread_count() = Threads.nthreads(:interactive) + Threads.nthreads(:default)

mutable struct AgentRunner{I<:IdleStrategy,A,H,C,N}
    idle_strategy::I
    agent::A
    error_handler::H
    error_counter::C
    @atomic is_started::Bool
    @atomic state::AgentRunnerState
    task::Union{StableTasks.StableTask,Nothing}
    lifecycle_lock::ReentrantLock
    """
    Create an agent runner and initialize it.

    # Arguments
    - `idle_strategy`: The idle strategy to use for the agent run loop.
    - `agent`: The agent to be run in this thread.
    - `error_handler`: Optional handler called before `on_error`.
    - `error_counter`: Optional counter incremented on errors.
    """
    function AgentRunner(idle_strategy::I, agent::A; error_handler=nothing, error_counter=nothing) where {I,A}
        new{I,A,typeof(error_handler),typeof(error_counter),managed_thread_count()}(
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
@inline set_runner_state!(runner::AgentRunner, state::AgentRunnerState) = @atomic :release runner.state = state

"""
    start_on_thread(runner::AgentRunner, threadid::Union{Nothing,Int} = nothing)

Start the Agent runner once. If `threadid` is supplied, the task is assigned to
that Julia runtime thread. This does not establish OS CPU affinity or scheduling
priority.

# Arguments
- `runner::AgentRunner`: The agent runner object.
- `threadid::Union{Nothing,Int}`: The Julia thread id to use. If `nothing`, the task is scheduled in the default pool.
"""
function start_on_thread(runner::AgentRunner, threadid::Union{Nothing,Int}=nothing)
    if threadid !== nothing
        thread_count = managed_thread_count()
        if threadid < 1 || threadid > thread_count
            throw(ArgumentError("threadid must identify an interactive or default Julia thread in 1:$thread_count"))
        end
    end

    lock(runner.lifecycle_lock)
    try
        state = runner_state(runner)
        if state === AGENT_RUNNER_CLOSED || state === AGENT_RUNNER_CLOSING
            throw(ArgumentError("AgentRunner is closed"))
        elseif state !== AGENT_RUNNER_INIT
            throw(ArgumentError("AgentRunner is already started"))
        end

        @atomic :release runner.is_started = true
        set_runner_state!(runner, AGENT_RUNNER_STARTING)

        try
            task = if threadid === nothing
                StableTasks.@spawn run(runner)
            else
                StableTasks.@spawnat threadid run(runner)
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
    close(runner::AgentRunner, retry_wait=0.1)

Request that the Agent stop and wait for its task and cleanup to finish.

Shutdown is cooperative: `do_work` must return periodically and must arrange for
any blocking operation to be woken by application-specific shutdown logic. Julia
does not provide a safe equivalent to Java's `Thread.interrupt`, so this method
never injects an exception into an already-started task.

`retry_wait` controls how often the task state is checked while closing. A value
of zero waits on the task directly.
"""
function Base.close(runner::AgentRunner, retry_wait::Real=0.1)
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
                    close_owner = true
                    break
                end
            elseif state === AGENT_RUNNER_RUNNING
                _, success = @atomicreplace runner.state AGENT_RUNNER_RUNNING => AGENT_RUNNER_CLOSING
                if success
                    task = runner.task
                    break
                end
            elseif state === AGENT_RUNNER_STARTING
                # start_on_thread publishes the task while holding lifecycle_lock,
                # so this state is only transiently observable by the task itself.
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
            try
                task === nothing || wait_for_task(task, retry_wait; propagate_failure=false)
            finally
                set_runner_state!(runner, AGENT_RUNNER_CLOSED)
            end
        end
    elseif task === nothing
        wait_for_close(runner, retry_wait)
    else
        wait_for_task(task, retry_wait; propagate_failure=true)
        wait_for_close(runner, retry_wait)
    end

    return nothing
end

"""
    is_started(runner::AgentRunner)

Return whether `start_on_thread` successfully began starting this runner.
"""
is_started(runner::AgentRunner) = @atomic :acquire runner.is_started

"""
    is_closed(runner::AgentRunner)

Check if the agent runner has completed cleanup.
"""
is_closed(runner::AgentRunner) = runner_state(runner) === AGENT_RUNNER_CLOSED
Base.isopen(runner::AgentRunner) = !is_closed(runner)

"""
    is_running(runner::AgentRunner)

Check if the agent runner owns and is executing the agent lifecycle.
"""
is_running(runner::AgentRunner) = runner_state(runner) === AGENT_RUNNER_RUNNING

function request_stop!(runner::AgentRunner)
    while true
        state = runner_state(runner)
        state === AGENT_RUNNER_RUNNING || return nothing
        _, success = @atomicreplace runner.state AGENT_RUNNER_RUNNING => AGENT_RUNNER_CLOSING
        success && return nothing
    end
end

function wait_for_task(task::StableTasks.StableTask, retry_wait::Real; propagate_failure::Bool)
    if retry_wait == 0
        if propagate_failure
            fetch(task)
        else
            while !istaskdone(task)
                yield()
            end
        end
        return nothing
    end

    while !istaskdone(task)
        timedwait(() -> istaskdone(task), retry_wait; pollint=poll_interval(retry_wait))
    end

    propagate_failure && fetch(task)
    return nothing
end

function wait_for_close(runner::AgentRunner, retry_wait::Real)
    while !is_closed(runner)
        if retry_wait == 0
            yield()
        else
            timedwait(() -> is_closed(runner), retry_wait; pollint=poll_interval(retry_wait))
        end
    end
    return nothing
end

@inline poll_interval(retry_wait::Real) = min(max(retry_wait / 10, 0.001), 0.01)

"""
    wait(runner::AgentRunner)

Wait for the agent runner to finish. A failed runner task is propagated as a
`TaskFailedException`.
"""
function Base.wait(runner::AgentRunner)
    lock(runner.lifecycle_lock)
    task, state = try
        runner.task, runner_state(runner)
    finally
        unlock(runner.lifecycle_lock)
    end

    if task === nothing
        state === AGENT_RUNNER_CLOSING && wait_for_close(runner, 0)
        return nothing
    end
    fetch(task)
    wait_for_close(runner, 0)
    return nothing
end

function run(runner::AgentRunner)
    while runner_state(runner) === AGENT_RUNNER_STARTING
        yield()
    end

    _, claimed = @atomicreplace runner.state AGENT_RUNNER_STARTED => AGENT_RUNNER_RUNNING
    claimed || return nothing

    agent = runner.agent
    try
        try
            on_start(agent)
        catch e
            request_stop!(runner)
            handle_error(runner.error_handler, runner.error_counter, agent, e)
        end

        while is_running(runner)
            run_loop(runner)
        end
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
        handle_error(runner.error_handler, runner.error_counter, runner.agent, e)
    end
    return nothing
end

@inline function run_loop(runner::AgentRunner)
    agent = runner.agent
    idle_strategy = runner.idle_strategy
    try
        while is_running(runner)
            idle(idle_strategy, do_work(agent))
        end
    catch e
        handle_runner_error(runner, agent, e)
    end
    return nothing
end

@inline function run_loop(runner::AgentRunner{I,A,H,C,1}) where {I<:IdleStrategy,A,H,C}
    agent = runner.agent
    idle_strategy = runner.idle_strategy
    iterations = 0
    try
        while is_running(runner)
            idle(idle_strategy, do_work(agent))
            iterations += 1
            if (iterations & (SINGLE_THREAD_SAFEPOINT_INTERVAL - 1)) == 0
                GC.safepoint()
            end
        end
    catch e
        handle_runner_error(runner, agent, e)
    end
    return nothing
end

@noinline function handle_runner_error(runner::AgentRunner, agent, e)
    if e isa AgentTerminationException || e isa InterruptException
        request_stop!(runner)
    else
        try
            handle_error(runner.error_handler, runner.error_counter, agent, e)
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

Base.isready(runner::AgentRunner) = is_running(runner)

export AgentRunner, start_on_thread
