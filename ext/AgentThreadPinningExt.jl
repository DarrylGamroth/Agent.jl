# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0

module AgentThreadPinningExt

using Agent
using ThreadPinning

function pin_assigned_thread!(threadid::Int, cpuid::Int)
    Sys.islinux() || throw(
        ArgumentError("CPU pinning through ThreadPinning.jl is supported only on Linux"),
    )
    ThreadPinning.pinthread(cpuid; threadid)
    return nothing
end

end # module AgentThreadPinningExt
