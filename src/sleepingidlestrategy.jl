# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    struct SleepingIdleStrategy <: IdleStrategy

When idle, this strategy sleeps for a specified period in nanoseconds.

This struct uses `Libc.nanosleep` to idle.
"""
struct SleepingIdleStrategy <: IdleStrategy
    sleeptime::Int
    function SleepingIdleStrategy(sleeptime)
        sleeptime <= 0 && error("sleeptime must be positive")
        sleeptime >= 1_000_000_000 && error("sleeptime must be less than 1_000_000_000 nanoseconds")
        new(sleeptime)
    end
end

SleepingIdleStrategy() = SleepingIdleStrategy(1_000)

function idle(strategy::SleepingIdleStrategy)
    park(strategy.sleeptime)
end

alias(::SleepingIdleStrategy) = "sleep-ns"

export SleepingIdleStrategy
