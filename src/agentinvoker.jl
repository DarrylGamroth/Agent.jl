"""
    AgentInvoker(agent; error_handler=nothing, error_counter=nothing)

Drive an agent from a caller-owned loop without creating a task. This type is
not thread-safe. Use `invoke` for Agrona-compatible checked invocation or
`invoke_unchecked` when the outer loop deliberately owns exception handling.
"""
mutable struct AgentInvoker{A,H,C}
    agent::A
    error_handler::H
    error_counter::C
    is_started::Bool
    is_running::Bool
    is_closed::Bool

    function AgentInvoker(agent::A; error_handler=nothing, error_counter=nothing) where {A}
        validate_error_counter(error_counter)
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

Return whether startup has been attempted.
"""
is_started(invoker::AgentInvoker) = invoker.is_started

"""
    is_running(invoker::AgentInvoker)

Return whether the invoker is accepting duty-cycle invocations.
"""
is_running(invoker::AgentInvoker) = invoker.is_running

"""
    is_closed(invoker::AgentInvoker)

Return whether cleanup has been attempted.
"""
is_closed(invoker::AgentInvoker) = invoker.is_closed

"""
    agent(invoker::AgentInvoker)

Return the agent owned by this invoker.
"""
agent(invoker::AgentInvoker) = invoker.agent

"""
    start(invoker::AgentInvoker)

Call `on_start` once. A startup failure is reported without incrementing the
work-error counter, then the invoker is closed.
"""
function start(invoker::AgentInvoker)
    invoker.is_started && return nothing

    invoker.is_started = true
    try
        on_start(invoker.agent)
        invoker.is_running = true
    catch e
        try
            report_error(invoker.error_handler, invoker.agent, e)
        finally
            close(invoker)
        end
    end
    return nothing
end

"""
    invoke(invoker::AgentInvoker)

Invoke one duty cycle and return its work count. Errors are handled according
to the Agrona invoker protocol: ordinary work errors are counted and reported,
handled errors leave the invoker running, and agent termination closes it.
Returns zero when the invoker is not running or when an error was handled.
"""
function invoke(invoker::AgentInvoker)
    invoker.is_running || return 0
    try
        return do_work(invoker.agent)
    catch e
        handle_error(invoker, e)
        return 0
    end
end

"""
    invoke_unchecked(invoker::AgentInvoker)

Invoke one duty cycle without catching exceptions. Returns zero when the
invoker is not running. This is intended for loops that centralise exception
handling outside the hot path.
"""
invoke_unchecked(invoker::AgentInvoker) =
    invoker.is_running ? do_work(invoker.agent) : 0

"""
    handle_error(invoker::AgentInvoker, error)

Apply invoker error semantics to an exception caught around
`invoke_unchecked`. Ordinary errors that are successfully reported do not stop
the invoker.
"""
@noinline function handle_error(invoker::AgentInvoker, e)
    if e isa InterruptException
        close(invoker)
    elseif e isa AgentTerminationException
        invoker.is_running = false
        try
            is_expected(e) || report_error(invoker.error_handler, invoker.agent, e)
        finally
            close(invoker)
        end
    else
        try
            handle_error(invoker.error_handler, invoker.error_counter, invoker.agent, e)
        catch on_error_e
            if on_error_e isa AgentTerminationException
                invoker.is_running = false
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

Stop the invoker and call `on_close` once. Cleanup failures are reported
without incrementing the work-error counter.
"""
function Base.close(invoker::AgentInvoker)
    invoker.is_closed && return nothing

    invoker.is_running = false
    invoker.is_closed = true
    try
        on_close(invoker.agent)
    catch e
        report_error(invoker.error_handler, invoker.agent, e)
    end
    return nothing
end

export AgentInvoker,
    agent,
    handle_error,
    invoke_unchecked,
    is_closed,
    is_running,
    is_started,
    start
