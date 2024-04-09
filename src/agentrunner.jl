"""
Agent runner containing an `Agent` which is run on a `Task`.
Note: An instance can only be started once then discarded.
"""
mutable struct AgentRunner{I<:IdleStrategy,A<:AbstractAgent}
    idle_strategy::I
    agent::A
    task::Task
    @atomic is_started::Bool
    @atomic is_closed::Bool
    @atomic is_running::Bool
    AgentRunner{I,A}() where {I,A} = new()
end

"""
Create an agent runner and initialize it.

# Arguments
- `idle_strategy`: The idle strategy to use for the agent run loop.
- `agent`: The agent to be run in this thread.

# Returns
- An initialized `AgentRunner` object.

"""
function AgentRunner(idle_strategy::I, agent::A) where {I<:IdleStrategy,A<:AbstractAgent}
    runner = AgentRunner{I,A}()
    runner.idle_strategy = idle_strategy
    runner.agent = agent
    @atomic runner.is_started = false
    @atomic runner.is_closed = false
    @atomic runner.is_running = false
    runner.task = @task run(runner)
    return runner
end

"""
    start(runner::AgentRunner)

    Start the Agent running. Start may be called only once and is invalid after close has been called.

# Arguments
- `runner::AgentRunner`: The agent runner object.

"""
function start(runner::AgentRunner)
    if is_closed(runner)
        throw(ArgumentError("AgentRunner is closed"))
    end

    _, success = @atomicreplace runner.is_started false => true
    if !success
        throw(ArgumentError("AgentRunner is already started"))
    end

    schedule(runner.task)
end

"""
    close(runner::AgentRunner)

Stop the running Agent and cleanup.

This function will wait for the agent task to exit.

# Arguments
- `runner::AgentRunner`: The agent runner object.
"""
function close(runner::AgentRunner)
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

function run(runner::AgentRunner)
    try
        is_running!(runner, true)
        try
            on_start(runner.agent)
        catch e
            throw(e)
        end

        while !is_closed(runner)
            do_work(runner)
        end

        try
            on_close(runner.agent)
        catch e
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
        else
            on_error(agent, e)
        end
    end
end

export AgentRunner, start, close
