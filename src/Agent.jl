# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
    Agent

Agrona-inspired agents, runners, invokers, composites, and idle strategies for
Julia. Agents are plain Julia values that implement the `Agent.do_work`
protocol and optional lifecycle callbacks.
"""
module Agent

using StableTasks

include("idlestrategy.jl")
include("backoffidlestrategy.jl")
include("busyspinidlestrategy.jl")
include("noopidlestrategy.jl")
include("sleepingidlestrategy.jl")
include("sleepingmillisidlestrategy.jl")
include("yieldingidlestrategy.jl")
include("controllableidlestrategy.jl")
include("abstractagent.jl")
include("errorhandling.jl")
include("compositeagent.jl")
include("dynamiccompositeagent.jl")
include("agentinvoker.jl")
include("agentrunner.jl")

end # module Agent
