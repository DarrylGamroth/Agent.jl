"""
Agent runner containing an `Agent` which is run on a `Task`.
Note: An instance can only be started once then discarded.
"""
mutable struct AgentRunner{I<:IdleStrategy,A<:AbstractAgent}
    idle_strategy::I
    agent::A
    @atomic is_started::Bool
    @atomic is_closed::Bool
    @atomic is_running::Bool
    task
    """
    Create an agent runner and initialize it.

    # Arguments
    - `idle_strategy`: The idle strategy to use for the agent run loop.
    - `agent`: The agent to be run in this thread.

    # Returns
    - An initialized `AgentRunner` object.

    """
    AgentRunner(idle_strategy::I, agent::A) where {I,A} = new{I,A}(idle_strategy, agent, false, false, false)
end

# Define a default threading function
default_thread_factory(f) = Threads.@spawn f()

"""
    start_on_thread(runner::AgentRunner, factory::Function = default_thread_factory)

    Start the Agent running. Start may be called only once and is invalid after close has been called.

# Arguments
- `runner::AgentRunner`: The agent runner object.
- `factory::Function`: The function to use to start the agent. Default is `Threads.@spawn`.

"""
function start_on_thread(runner::AgentRunner, factory::Function=default_thread_factory)
    if is_closed(runner)
        throw(ArgumentError("AgentRunner is closed"))
    end

    _, success = @atomicreplace runner.is_started false => true
    if !success
        throw(ArgumentError("AgentRunner is already started"))
    end

    # Use the factory function to execute the run function in a thread
    runner.task = factory(() -> run(runner))
end

"""
    close(runner::AgentRunner)

Stop the running Agent and cleanup.

This function will wait for the agent task to exit.

# Arguments
- `runner::AgentRunner`: The agent runner object.
"""
function Base.close(runner::AgentRunner)
    # schedule(runner.task, AgentTerminationException(); error=true)
    _, success = @atomicreplace :sequentially_consistent runner.is_closed false => true
    if success
        wait(runner.task)
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
    task(runner::AgentRunner)

Get the task associated with the agent runner.

# Arguments
- `runner::AgentRunner`: The agent runner object.

# Returns
- `Task`: The task associated with the agent runner. Returns `undef` if the runner is not started.
"""
task(runner::AgentRunner) = runner.task

function run(runner::AgentRunner)
    agent = runner.agent
    try
        is_running!(runner, true)
        on_start(agent)

        while !is_closed(runner)
            do_work(runner)
        end

        on_close(agent)
    catch e
        if e isa Exception
            @error "Exception caught:" exception = (e, catch_backtrace())
            throw(e)
        end
    finally
        is_running!(runner, false)
    end
end

@inline function do_work(runner::AgentRunner)
    agent = runner.agent
    idle_strategy = runner.idle_strategy
    try
        while !is_closed(runner)
            workcount = do_work(agent)
            idle(idle_strategy, workcount)
        end
    catch e
        if e isa AgentTerminationException
            is_closed!(runner, true)
        elseif e isa Exception
            try
                on_error(agent, e)
            catch e
                if e isa AgentTerminationException
                    is_closed!(runner, true)
                else
                    throw(e)
                end
            end
        else
            throw(e)
        end
    end
end

export AgentRunner, start_on_thread, close, task
