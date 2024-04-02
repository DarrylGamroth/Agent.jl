"""
    struct SleepingIdleStrategy <: IdleStrategy

When idle, this strategy sleeps for a specified period in nanoseconds.

This struct uses `Libc.nanosleep` to idle.
"""
struct SleepingIdleStrategy <: IdleStrategy
    sleeptime::Int
    function SleepingIdleStrategy(sleeptime)
        sleeptime >= 1_000_000_000 && error("sleeptime must be less than 1_000_000_000 nanoseconds")
        new(sleeptime)
    end
end

function idle(strategy::SleepingIdleStrategy)
    park(strategy.sleeptime)
end

export SleepingIdleStrategy
