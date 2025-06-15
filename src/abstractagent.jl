"""
    An Agent is scheduled to do work on a thread on a duty cycle. Each Agent should have a defined role in a system.

    # Lifecycle Methods
    - `on_start()`: This method is called when the agent starts running.
    - `do_work()`: This method is called repeatedly by the same thread to perform the agent's work.
    - `on_close()`: This method is called when the agent finishes running, either successfully or due to failure.

    All lifecycle methods are called by the same thread and in a thread-safe manner if the agent runs successfully.
    `on_close()` will be called if the agent fails to run.
"""

"""
    struct AgentTerminationException <: Exception

AgentTerminationException is an exception that an agent can throw to stop itself from running.

"""
struct AgentTerminationException <: Exception end

"""
    do_work(agent)

Perform the main work of the agent.

# Arguments
- `agent`: The agent object.

# Throws
- `MethodError`: If the method is not implemented.

"""
function do_work end

"""
    on_start(agent)

Perform actions when the agent starts.

# Arguments
- `agent`: The agent object.

"""
function on_start(agent)
end

"""
    on_close(agent)

Perform actions when the agent is closed.

# Arguments
- `agent`: The agent object.

"""
function on_close(agent)
end

"""
    on_error(agent, error)

Perform actions when an error occurs.

# Arguments
- `agent`: The agent object.
- `error`: The object that was thrown.

"""
function on_error(agent, error)
    throw(error)
end

"""
    name(agent)

Return the name of the agent.

# Arguments
- `agent::AbstractAgent`: The agent object.

"""
function name(agent)
    throw(MethodError(name, (agent,)))
end

export AgentTerminationException
