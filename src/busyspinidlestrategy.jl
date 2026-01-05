"""
    struct BusySpinIdleStrategy <: IdleStrategy

    Busy spin strategy targeted at lowest possible latency. This strategy will monopolise a thread to achieve the lowest
    possible latency. Useful for creating bubbles in the execution pipeline of tight busy spin loops with no other logic
    than status checks on progress.
"""
struct BusySpinIdleStrategy <: IdleStrategy
end

function idle(::BusySpinIdleStrategy)
    ccall(:jl_cpu_pause, Cvoid, ())
end

alias(::BusySpinIdleStrategy) = "spin"

export BusySpinIdleStrategy
