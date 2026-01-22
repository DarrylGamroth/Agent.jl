"""
Agent invoker which allows an Agent to be driven without creating a Task.
"""
mutable struct AgentInvoker{A,H,C}
    agent::A
    error_handler::H
    error_counter::C
    is_started::Bool
    is_running::Bool
    is_closed::Bool

    function AgentInvoker(agent::A; error_handler=nothing, error_counter=nothing) where {A}
        new{A,typeof(error_handler),typeof(error_counter)}(
            agent,
            error_handler,
            error_counter,
            false,
            false,
            false,
        )
    end
end

"""
    is_started(invoker::AgentInvoker)

Return whether the invoker has started the agent.
"""
is_started(invoker::AgentInvoker) = invoker.is_started

"""
    is_running(invoker::AgentInvoker)

Return whether the invoker is running the agent.
"""
is_running(invoker::AgentInvoker) = invoker.is_running

"""
    is_closed(invoker::AgentInvoker)

Return whether the invoker has been closed.
"""
is_closed(invoker::AgentInvoker) = invoker.is_closed

"""
    agent(invoker::AgentInvoker)

Return the agent owned by this invoker.
"""
agent(invoker::AgentInvoker) = invoker.agent

"""
    start(invoker::AgentInvoker)

Start the invoker and call `on_start` once.
"""
function start(invoker::AgentInvoker)
    if invoker.is_started
        return
    end

    invoker.is_started = true
    try
        on_start(invoker.agent)
        invoker.is_running = true
    catch e
        handle_error(invoker.error_handler, invoker.error_counter, invoker.agent, e)
        close(invoker)
    end
    return nothing
end

"""
    invoke(invoker::AgentInvoker)

Invoke `do_work` once and return the work count. This method does not handle
exceptions and is intended for hot-path use.
"""
invoke(invoker::AgentInvoker) = invoker.is_running ? do_work(invoker.agent) : 0

"""
    handle_error(invoker::AgentInvoker, error)

Handle errors thrown by `invoke` when the caller wraps the outer loop in a single
`try`/`catch`.
"""
@noinline function handle_error(invoker::AgentInvoker, e)
    invoker.is_running = false
    if e isa InterruptException
        return nothing
    elseif e isa AgentTerminationException
        try
            handle_error(invoker.error_handler, invoker.error_counter, invoker.agent, e)
        catch on_error_e
            if !(on_error_e isa AgentTerminationException)
                rethrow(on_error_e)
            end
        end
        close(invoker)
    else
        try
            handle_error(invoker.error_handler, invoker.error_counter, invoker.agent, e)
        catch on_error_e
            if on_error_e isa AgentTerminationException
                close(invoker)
            else
                rethrow(on_error_e)
            end
        end
    end
    return nothing
end

"""
    close(invoker::AgentInvoker)

Stop the invoker and call `on_close` once.
"""
function Base.close(invoker::AgentInvoker)
    if invoker.is_closed
        return
    end

    invoker.is_running = false
    invoker.is_closed = true
    try
        on_close(invoker.agent)
    catch e
        handle_error(invoker.error_handler, invoker.error_counter, invoker.agent, e)
    end
    return nothing
end

export AgentInvoker, agent, handle_error, is_closed, is_running, is_started, start
