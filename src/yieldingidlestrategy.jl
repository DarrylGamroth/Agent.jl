# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    struct YieldingIdleStrategy <: IdleStrategy

    A type of `IdleStrategy` that calls `yield()` when the work count is zero.
"""
struct YieldingIdleStrategy <: IdleStrategy
end

function idle(::YieldingIdleStrategy)
    yield()
end

alias(::YieldingIdleStrategy) = "yield"

export YieldingIdleStrategy
