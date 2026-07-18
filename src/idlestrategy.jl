"""
    Idle strategy for use by threads when they do not have work to do.

    **Note regarding implementor state:**
    Some implementations are stateful and must be owned by one runner. Do not
    share a stateful strategy between concurrently executing agents.

    **Note regarding potential for TTSP (Time To Safe Point) issues:**
    A counted, non-allocating loop can prevent Julia's garbage collector from
    reaching a safepoint. `AgentRunner` inserts periodic GC safepoints for this
    reason. Custom loops that call an idle strategy directly must provide their
    own `GC.safepoint()` or another operation that reaches a safepoint.
"""
abstract type IdleStrategy end

"""
    idle(strategy::IdleStrategy)

    Perform current idle action.

# Arguments
- `strategy::IdleStrategy`: The idle strategy object.

# Throws
- `MethodError`: If the method is not implemented.

"""
function idle(strategy::IdleStrategy)
    throw(MethodError(idle, (strategy,)))
end

"""
    Perform current idle action (e.g. nothing/yield/sleep). This method signature expects users to call into it on
    every work 'cycle'. The implementations may use the indication `workCount > 0` to reset internal backoff
    state. This method works well with 'work' APIs which follow the following rules:

    - 'work' returns a value larger than 0 when some work has been done
    - 'work' returns 0 when no work has been done
    - 'work' may return error codes which are less than 0, but which amount to no work has been done

    Callers are expected to follow this pattern:

    ```julia
    while is_running
        idle(idleStrategy, doWork())
    end
    ```

    # Arguments
    - `workCount::Integer`: The number of work performed in the last duty cycle.
"""
@inline function idle(strategy::IdleStrategy, workcount::Integer)
    if workcount > 0
        reset(strategy)
    else
        idle(strategy)
    end
end

"""
    reset(strategy::IdleStrategy)

Reset the internal state in preparation for entering an idle state again.
"""
reset(::IdleStrategy) = nothing

"""
    alias(strategy::IdleStrategy)

Return a short name for the idle strategy.
"""
alias(::IdleStrategy) = ""

if Sys.isunix()
    struct TimeSpec
        tv_sec::Int64
        tv_nsec::Int64
    end
    "park suspends the thread without the Julia scheduler knowing about it"
    function park(nsec::Int64)
        ts = TimeSpec(0, nsec)
        @ccall nanosleep(ts::Ref{TimeSpec}, C_NULL::Ref{Cvoid})::Cint
    end
elseif Sys.iswindows()
    function park(nsec::Int64)
        # Sleep is in milliseconds
        sleep_time = nsec ÷ 1_000_000 + 1
        @ccall Sleep(sleep_time::Cuint)::Cvoid
    end
else
    error("park undefined for this OS")
end

export IdleStrategy, alias
