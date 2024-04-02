@enum BackoffIdleState begin
    BACKOFF_IDLE_STATE_NOT_IDLE
    BACKOFF_IDLE_STATE_SPINNING
    BACKOFF_IDLE_STATE_YIELDING
    BACKOFF_IDLE_STATE_PARKING
end

"""
    struct BackoffIdleStrategy <: IdleStrategy

Idling strategy for threads when they have no work to do.

Spin for `max_spins`, then `yield()` for `max_yields`, then `nanosleep(max_park_period_ns)` on an exponential backoff to `max_park_period_ns`.
"""
mutable struct BackoffIdleStrategy <: IdleStrategy
    const pad1::NTuple{64,Int8} # Padding to avoid false sharing
    const max_spins::Int
    const max_yields::Int
    const min_park_period_ns::Int
    const max_park_period_ns::Int
    spins::Int
    yields::Int
    park_period_ns::Int
    state::BackoffIdleState
    const pad2::NTuple{64,Int8} # Padding to avoid false sharing
    function BackoffIdleStrategy(max_spins, max_yields, min_park_period_ns, max_park_period_ns)
        new(ntuple(x -> Int8(0), 64), max_spins, max_yields, min_park_period_ns, max_park_period_ns,
        0, 0, 0, BACKOFF_IDLE_STATE_NOT_IDLE, ntuple(x -> Int8(0), 64))
    end
end

function BackoffIdleStrategy()
    default_max_spins = 10
    default_max_yields = 5
    default_min_park_time = 1_000 # 1 microsecond
    default_max_park_time = 1_000_000 # 1 milisecond
    return BackoffIdleStrategy(default_max_spins, default_max_yields, default_min_park_time, default_max_park_time)
end

@inline function idle(strategy::BackoffIdleStrategy)
    if strategy.state == BACKOFF_IDLE_STATE_NOT_IDLE
        strategy.state = BACKOFF_IDLE_STATE_SPINNING
        strategy.spins += 1
    elseif strategy.state == BACKOFF_IDLE_STATE_SPINNING
        strategy.spins += 1
        if strategy.spins > strategy.max_spins
            strategy.state = BACKOFF_IDLE_STATE_YIELDING
            strategy.yields = 0
        end
    elseif strategy.state == BACKOFF_IDLE_STATE_YIELDING
        strategy.yields += 1
        if strategy.yields > strategy.max_yields
            strategy.state = BACKOFF_IDLE_STATE_PARKING
            strategy.park_period_ns = strategy.min_park_period_ns
        else
            yield()
        end
    elseif strategy.state === BACKOFF_IDLE_STATE_PARKING
        park(strategy.park_period_ns)
        strategy.park_period_ns = min(strategy.park_period_ns << 1, strategy.max_park_period_ns)
    end
    return
end

@inline function reset(strategy::BackoffIdleStrategy)
    strategy.spins = 0
    strategy.yields = 0
    strategy.park_period_ns = strategy.min_park_period_ns
    strategy.state = BACKOFF_IDLE_STATE_NOT_IDLE
end

export BackoffIdleStrategy
