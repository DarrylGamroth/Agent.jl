"""
    struct YieldingIdleStrategy <: IdleStrategy

    A type of `IdleStrategy` that calls `yield()` when the work count is zero.
"""
struct YieldingIdleStrategy <: IdleStrategy
end

function idle(::YieldingIdleStrategy)
    yield()
end

export YieldingIdleStrategy
