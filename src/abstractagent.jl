"""
    An Agent is scheduled to do work on a thread on a duty cycle. Each Agent should have a defined role in a system.

    # Lifecycle Methods
    - `on_start()`: This method is called when the agent starts running.
    - `do_work()`: This method is called repeatedly by the same thread to perform the agent's work.
    - `on_close()`: This method is called when the agent finishes running, either successfully or due to failure.

    All lifecycle methods are called by the same thread and in a thread-safe manner if the agent runs successfully.
    `on_close()` will be called if the agent fails to run.
"""
abstract type AbstractAgent end

"""
    struct AgentTerminationException <: Exception

AgentTerminationException is an exception that an agent can throw to stop itself from running.

"""
struct AgentTerminationException <: Exception end

"""
    do_work(agent::AbstractAgent)

Perform the main work of the agent.

# Arguments
- `agent::AbstractAgent`: The agent object.

# Throws
- `MethodError`: If the method is not implemented.

"""
function do_work(agent::AbstractAgent)
    throw(MethodError(agent, "do_work"))
end

"""
    on_start(agent::AbstractAgent)

Perform actions when the agent starts.

# Arguments
- `agent::AbstractAgent`: The agent object.

"""
function on_start(::AbstractAgent)
end

"""
    on_close(agent::AbstractAgent)

Perform actions when the agent is closed.

# Arguments
- `agent::AbstractAgent`: The agent object.

"""
function on_close(::AbstractAgent)
end

"""
    on_error(agent::AbstractAgent, error::Exception)

Perform actions when an error occurs.

# Arguments
- `agent::AbstractAgent`: The agent object.
- `error::Exception`: The error that occurred.

"""
function on_error(agent::AbstractAgent, e::Exception)
end

"""
    name(agent::AbstractAgent)

Return the name of the agent.

# Arguments
- `agent::AbstractAgent`: The agent object.

"""
function name(agent::AbstractAgent)
    throw(MethodError(agent, "name"))
end

export AbstractAgent, AgentTerminationException
