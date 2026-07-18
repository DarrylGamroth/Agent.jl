# Copyright 2014-2025 Real Logic Limited.
# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Ported from Agrona and substantially modified for Julia.

"""
Error reporting utilities shared by agent runners and invokers.

Only errors from `do_work` increment the optional error counter. Lifecycle and
termination errors are reported without incrementing it, matching Agrona's
agent protocol.
"""

increment_error_counter!(::Nothing) = nothing

function increment_error_counter!(counter::Threads.Atomic{T}) where {T<:Integer}
    Threads.atomic_add!(counter, one(T))
    return nothing
end

function validate_error_counter(error_counter)
    if error_counter !== nothing && !(error_counter isa Threads.Atomic{<:Integer})
        throw(ArgumentError("error_counter must be nothing or Threads.Atomic{<:Integer}"))
    end
    return error_counter
end

function report_error(error_handler, agent, error)
    if error_handler !== nothing
        error_handler(agent, error)
    end
    on_error(agent, error)
    return nothing
end

function handle_error(error_handler, error_counter, agent, error)
    increment_error_counter!(error_counter)
    report_error(error_handler, agent, error)
    return nothing
end
