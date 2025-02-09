"""
Agent runner containing an `Agent` which is run on a `Task`.
Note: An instance can only be started once then discarded.
"""
mutable struct AgentRunner{I<:IdleStrategy,A}
    idle_strategy::I
    agent::A
    @atomic is_started::Bool
    @atomic is_closed::Bool
    @atomic is_running::Bool
    task::StableTasks.StableTask{Nothing}
    """
    Create an agent runner and initialize it.

    # Arguments
    - `idle_strategy`: The idle strategy to use for the agent run loop.
    - `agent`: The agent to be run in this thread.
    """
    function AgentRunner(idle_strategy::I, agent::A) where {I,A}
        new{I,A}(idle_strategy, agent, false, false, false)
    end
end

"""
    start_on_thread(runner::AgentRunner, threadid::Union{Nothing,Int} = nothing)

    Start the Agent running. Start may be called only once and is invalid after close has been called.

# Arguments
- `runner::AgentRunner`: The agent runner object.
- `threadid::Union{Nothing,Int}`: The thread id to run the agent on. If `nothing`, the agent will be scheduled by the runtime.
"""
function start_on_thread(runner::AgentRunner, threadid::Union{Nothing,Int}=nothing)
    if is_closed(runner)
        throw(ArgumentError("AgentRunner is closed"))
    end

    _, success = @atomicreplace runner.is_started false => true
    if !success
        throw(ArgumentError("AgentRunner is already started"))
    end

    if threadid === nothing
        runner.task = StableTasks.@spawn run(runner)
    else
        runner.task = StableTasks.@spawnat threadid run(runner)
    end
end

"""
    close(runner::AgentRunner)

Stop the running Agent and cleanup.

This function will wait for the agent task to exit.

# Arguments
- `runner::AgentRunner`: The agent runner object.
"""
function Base.close(runner::AgentRunner, timeout=0.1)
    is_running!(runner, false)

    t = runner.task

    if !istaskdone(t) && !istaskfailed(t)
        while true
            try
                is_closed(runner) && return

                timedwait(() -> istaskdone(t), timeout)

                if istaskdone(t) || is_closed(runner)
                    return
                end

                if !istaskfailed(t)
                    schedule(t, InterruptException(), error=true)
                end
            catch e
                if e isa InterruptException
                    if !is_closed(runner) && !istaskfailed(t)
                        schedule(t, InterruptException(), error=true)
                        yield()
                    end
                end
            end
        end
    end
end

"""
    is_closed(runner::AgentRunner)

Check if the agent runner is closed.

# Arguments
- `runner::AgentRunner`: The agent runner object.

# Returns
- `Bool`: `true` if the agent runner is closed, `false` otherwise.
"""
is_closed(runner::AgentRunner) = @atomic :acquire runner.is_closed
Base.isopen(runner::AgentRunner) = !is_closed(runner)

"""
    is_closed!(runner::AgentRunner, value::Bool)

Set the closed status of the agent runner.

# Arguments
- `runner::AgentRunner`: The agent runner object.
- `value::Bool`: The new closed status.

# Returns
- `Nothing`
"""
is_closed!(runner::AgentRunner, value::Bool) = @atomic :release runner.is_closed = value

"""
    is_running(runner::AgentRunner)

Check if the agent runner is running.

# Arguments
- `runner::AgentRunner`: The agent runner object.

# Returns
- `Bool`: `true` if the agent runner is running, `false` otherwise.
"""
is_running(runner::AgentRunner) = @atomic :acquire runner.is_running

"""
    is_running!(runner::AgentRunner, value::Bool)

Set the running status of the agent runner.

# Arguments
- `runner::AgentRunner`: The agent runner object.
- `value::Bool`: The new running status.

# Returns
- `Nothing`
"""
is_running!(runner::AgentRunner, value::Bool) = @atomic :release runner.is_running = value

"""
    wait(runner::AgentRunner)

Wait for the agent runner to finish.

# Arguments
- `runner::AgentRunner`: The agent runner object.
"""
Base.wait(runner::AgentRunner) = wait(task(runner))

function run(runner::AgentRunner)
    agent = runner.agent
    try
        is_running!(runner, true)
        try
            on_start(agent)
        catch e
            is_running!(runner, false)
            on_error(agent, e)
            throw(e)
        end

        while is_running(runner)
            do_work(runner)
        end

        try
            on_close(agent)
        catch e
            on_error(agent, e)
            throw(e)
        end
    finally
        is_closed!(runner, true)
    end
    nothing
end

@inline function do_work(runner::AgentRunner)
    agent = runner.agent
    idle_strategy = runner.idle_strategy
    try
        while is_running(runner)
            idle(idle_strategy, do_work(agent))
        end
    catch e
        if e isa AgentTerminationException
            is_running!(runner, false)
        elseif e isa InterruptException
            is_running!(runner, false)
            rethrow(e)
        else
            try
                on_error(agent, e)
            catch on_error_e
                if on_error_e isa AgentTerminationException
                    is_running!(runner, false)
                else
                    throw(on_error_e)
                end
            end
        end
    end
end

Base.isready(runner::AgentRunner) = is_running(runner)

export AgentRunner, start_on_thread, close
