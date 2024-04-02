"""
    struct NoOpIdleStrategy <: IdleStrategy

    Low-latency idle strategy to be employed in loops that do significant work on each iteration such that any
    work in the idle strategy would be wasteful.
"""
struct NoOpIdleStrategy <: IdleStrategy
end

function idle(::NoOpIdleStrategy)
    # No operation performed
end