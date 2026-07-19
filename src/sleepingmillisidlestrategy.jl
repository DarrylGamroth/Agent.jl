# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    struct SleepingMillisIdleStrategy <: IdleStrategy

When idle, this strategy sleeps for a specified period in milliseconds.

This struct uses `Base.sleep` to idle. Warning: Base.sleep allocates memory.
"""
struct SleepingMillisIdleStrategy <: IdleStrategy
    sleeptime::Float32
    function SleepingMillisIdleStrategy(sleeptime)
        sleeptime <= 0 && error("sleeptime must be positive")
        new(sleeptime / 1000)
    end
end

SleepingMillisIdleStrategy() = SleepingMillisIdleStrategy(1)

function idle(strategy::SleepingMillisIdleStrategy)
    sleep(strategy.sleeptime)
end

alias(::SleepingMillisIdleStrategy) = "sleep-ms"

export SleepingMillisIdleStrategy
