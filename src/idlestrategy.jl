"""
    Idle strategy for use by threads when they do not have work to do.

    **Note regarding implementor state:**
    Some implementations are known to be stateful, please note that you cannot safely assume implementations to be
    stateless. Where implementations are stateful it is recommended that implementation state is padded to avoid false
    sharing.

    **Note regarding potential for TTSP (Time To Safe Point) issues:**
    If the caller spins in a 'counted' loop, and the implementation does not include a safepoint poll this may cause a
    TTSP (Time To SafePoint) problem. If the implementation does not include a safepoint poll, then the caller should
    include a call to `GC.safepoint()` in the loop.
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
    throw(MethodError(strategy, "idle"))
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
    reset_idle_state()

Reset the internal state in preparation for entering an idle state again.
"""
reset(::IdleStrategy) = nothing

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

export IdleStrategy
