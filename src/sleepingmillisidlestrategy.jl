"""
    struct SleepingMillisIdleStrategy <: IdleStrategy

When idle, this strategy sleeps for a specified period in miliseconds.

This struct uses `Base.sleep` to idle. Warning: Base.sleep allocates memory.
"""
struct SleepingMillisIdleStrategy <: IdleStrategy
    sleeptime::Float32
    function SleepingMillisIdleStrategy(sleeptime)
        new(sleeptime / 1000)
    end
end

function idle(strategy::SleepingMillisIdleStrategy)
    sleep(strategy.sleeptime)
end