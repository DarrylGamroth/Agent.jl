# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    struct BusySpinIdleStrategy <: IdleStrategy

Issue a CPU pause hint while no work is available.

The strategy alone does not establish a dedicated thread. `start(runner)`
yields after every duty cycle, as does `start_on_thread(runner, id)` when the
target thread pool contains only one Julia runtime thread. Dedicated-loop
behavior requires explicit placement into a multi-thread pool with
`start_on_thread(runner, id)`; pass `cpuid` as well when Linux OS affinity is
required.

Even when pinned, the Julia runtime thread does not have exclusive ownership of
the CPU and Agent.jl does not change its OS scheduling priority.
"""
struct BusySpinIdleStrategy <: IdleStrategy
end

function idle(::BusySpinIdleStrategy)
    ccall(:jl_cpu_pause, Cvoid, ())
end

alias(::BusySpinIdleStrategy) = "spin"

export BusySpinIdleStrategy
