# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

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

alias(::NoOpIdleStrategy) = "noop"

export NoOpIdleStrategy
