# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0

using Test
using Agent

@testset "AgentRunner Safepoint and Scheduler Liveness" begin
    default_threads = Threads.nthreads(:default)
    interactive_threads = Threads.nthreads(:interactive)
    thread_spec = interactive_threads == 0 ?
                  string(default_threads) :
                  string(default_threads, ",", interactive_threads)
    mode = Agent.managed_thread_count() == 1 ? "single" : "gc"
    child = joinpath(@__DIR__, "runner_liveness_child.jl")
    project = dirname(@__DIR__)
    command = `$(Base.julia_cmd()) --startup-file=no --project=$project --threads=$thread_spec $child $mode`

    mktemp() do _, output
        process = run(pipeline(command; stdout=output, stderr=output); wait=false)
        result = timedwait(() -> process_exited(process), 30.0; pollint=0.05)

        if result === :timed_out
            kill(process)
            timedwait(() -> process_exited(process), 5.0; pollint=0.05)
        end

        seekstart(output)
        child_output = read(output, String)
        exited = process_exited(process)
        succeeded = exited && success(process)
        if result !== :ok || !succeeded
            @error "runner liveness child failed" mode thread_spec child_output
        end
        @test result === :ok
        @test exited
        @test succeeded
        @test occursin("runner liveness: ok", child_output)
    end
end
