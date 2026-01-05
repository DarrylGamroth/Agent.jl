"""
    struct ControllableIdleStrategy <: IdleStrategy

Idle strategy controlled by a status indicator held in a `Ref` so the mode can be adjusted externally without
mutating the strategy itself.
"""
@enum ControllableIdleMode begin
    CONTROLLABLE_NOT_CONTROLLED = 0
    CONTROLLABLE_NOOP = 1
    CONTROLLABLE_BUSY_SPIN = 2
    CONTROLLABLE_YIELD = 3
    CONTROLLABLE_PARK = 4
end

struct ControllableIdleStrategy{R<:Ref{ControllableIdleMode}} <: IdleStrategy
    status_indicator::R
end

const CONTROLLABLE_PARK_PERIOD_NS = 1_000

function idle(strategy::ControllableIdleStrategy, workcount::Integer)
    if workcount > 0
        return
    end
    idle(strategy)
end

function idle(strategy::ControllableIdleStrategy)
    status = strategy.status_indicator[]
    if status == CONTROLLABLE_NOOP
        return
    elseif status == CONTROLLABLE_BUSY_SPIN
        ccall(:jl_cpu_pause, Cvoid, ())
    elseif status == CONTROLLABLE_YIELD
        yield()
    else
        park(CONTROLLABLE_PARK_PERIOD_NS)
    end
end

reset(::ControllableIdleStrategy) = nothing

alias(::ControllableIdleStrategy) = "controllable"

export ControllableIdleStrategy,
    ControllableIdleMode,
    CONTROLLABLE_NOT_CONTROLLED,
    CONTROLLABLE_NOOP,
    CONTROLLABLE_BUSY_SPIN,
    CONTROLLABLE_YIELD,
    CONTROLLABLE_PARK
