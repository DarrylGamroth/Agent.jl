# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    ControllableIdleMode

Operating modes supported by `ControllableIdleStrategy`.
"""
@enum ControllableIdleMode begin
    CONTROLLABLE_NOT_CONTROLLED = 0
    CONTROLLABLE_NOOP = 1
    CONTROLLABLE_BUSY_SPIN = 2
    CONTROLLABLE_YIELD = 3
    CONTROLLABLE_PARK = 4
end

@doc "Use the default park behavior." CONTROLLABLE_NOT_CONTROLLED
@doc "Perform no idle operation." CONTROLLABLE_NOOP
@doc "Issue a processor spin hint while idle." CONTROLLABLE_BUSY_SPIN
@doc "Yield to Julia's task scheduler while idle." CONTROLLABLE_YIELD
@doc "Park the Julia runtime thread briefly while idle." CONTROLLABLE_PARK

"""
    ControllableIdleStrategy([mode=CONTROLLABLE_NOT_CONTROLLED])

An idle strategy whose mode can be changed safely from another Julia thread
with `set_idle_mode!`. The mode is stored in an atomic field; ordinary `Ref`
values are intentionally not accepted because unsynchronised cross-thread
access is a data race in Julia.
"""
mutable struct ControllableIdleStrategy <: IdleStrategy
    @atomic mode::ControllableIdleMode

    function ControllableIdleStrategy(mode::ControllableIdleMode=CONTROLLABLE_NOT_CONTROLLED)
        new(mode)
    end
end

const CONTROLLABLE_PARK_PERIOD_NS = 1_000

"""
    idle_mode(strategy::ControllableIdleStrategy)

Return the currently published idle mode.
"""
idle_mode(strategy::ControllableIdleStrategy) = @atomic :acquire strategy.mode

"""
    set_idle_mode!(strategy::ControllableIdleStrategy, mode::ControllableIdleMode)

Publish a new idle mode and return `strategy`.
"""
function set_idle_mode!(strategy::ControllableIdleStrategy, mode::ControllableIdleMode)
    @atomic :release strategy.mode = mode
    return strategy
end

function idle(strategy::ControllableIdleStrategy, workcount::Integer)
    workcount > 0 && return nothing
    return idle(strategy)
end

function idle(strategy::ControllableIdleStrategy)
    status = idle_mode(strategy)
    if status == CONTROLLABLE_NOOP
        return nothing
    elseif status == CONTROLLABLE_BUSY_SPIN
        ccall(:jl_cpu_pause, Cvoid, ())
    elseif status == CONTROLLABLE_YIELD
        yield()
    else
        park(CONTROLLABLE_PARK_PERIOD_NS)
    end
    return nothing
end

reset(::ControllableIdleStrategy) = nothing

alias(::ControllableIdleStrategy) = "controllable"

export ControllableIdleStrategy,
    ControllableIdleMode,
    CONTROLLABLE_NOT_CONTROLLED,
    CONTROLLABLE_NOOP,
    CONTROLLABLE_BUSY_SPIN,
    CONTROLLABLE_YIELD,
    CONTROLLABLE_PARK,
    idle_mode,
    set_idle_mode!
