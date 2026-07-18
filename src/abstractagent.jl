"""
    AgentTerminationException([message]; expected=true)

Exception an agent can throw to stop its duty cycle. Expected terminations are
normal graceful shutdowns and are not reported to the error handler. Set
`expected=false` when termination itself should be reported as an error.

"""
struct AgentTerminationException <: Exception
    message::Union{Nothing,String}
    expected::Bool
end

AgentTerminationException() = AgentTerminationException(nothing, true)
AgentTerminationException(expected::Bool) = AgentTerminationException(nothing, expected)
AgentTerminationException(message::AbstractString; expected::Bool=true) =
    AgentTerminationException(String(message), expected)

"""
    is_expected(exception::AgentTerminationException)

Return whether an agent termination represents graceful shutdown.
"""
is_expected(exception::AgentTerminationException) = exception.expected

function Base.showerror(io::IO, exception::AgentTerminationException)
    print(io, "AgentTerminationException")
    exception.message === nothing || print(io, ": ", exception.message)
    return nothing
end

"""
    do_work(agent)

Perform the main work of the agent.

Runner lifecycle and duty-cycle methods are serialised by one owning task and
are never invoked concurrently by Agent.jl. A scheduler-managed task may
migrate between Julia runtime threads after yielding; only
`start_on_thread(runner, id)` guarantees one Julia runtime thread.

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
- `agent`: The agent object.

"""
function name(agent)
    throw(MethodError(name, (agent,)))
end

export AgentTerminationException, is_expected
