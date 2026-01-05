using Test
using Agent

@testset "DynamicCompositeAgent Tests" begin
    mutable struct DynAgent
        name::String
        started::Bool
        closed::Bool
        work_count::Int
    end

    DynAgent(name::String) = DynAgent(name, false, false, 0)

    Agent.name(agent::DynAgent) = agent.name
    Agent.on_start(agent::DynAgent) = (agent.started = true)
    Agent.on_close(agent::DynAgent) = (agent.closed = true)
    Agent.do_work(agent::DynAgent) = (agent.work_count += 1; 1)

    @testset "Lifecycle and Add/Remove" begin
        a = DynAgent("a")
        b = DynAgent("b")
        dyn = DynamicCompositeAgent("dynamic", a)

        @test Agent.name(dyn) == "dynamic"
        @test status(dyn) == Agent.INIT
        @test_throws ArgumentError try_add(dyn, b)

        Agent.on_start(dyn)
        @test status(dyn) == Agent.ACTIVE
        @test a.started

        @test try_add(dyn, b)
        @test !has_add_completed(dyn)

        work = Agent.do_work(dyn)
        @test work == 2
        @test has_add_completed(dyn)
        @test b.started

        @test try_remove(dyn, a)
        @test !has_remove_completed(dyn)

        work = Agent.do_work(dyn)
        @test work == 1
        @test has_remove_completed(dyn)
        @test a.closed
        @test b.work_count >= 1

        Agent.on_close(dyn)
        @test status(dyn) == Agent.CLOSED
        @test b.closed
    end

    @testset "Close Error Aggregation" begin
        mutable struct CloseErrorAgent
            name::String
        end

        Agent.name(agent::CloseErrorAgent) = agent.name
        Agent.on_start(agent::CloseErrorAgent) = nothing
        Agent.do_work(agent::CloseErrorAgent) = 0
        Agent.on_close(agent::CloseErrorAgent) = error("close error")

        a = CloseErrorAgent("a")
        b = CloseErrorAgent("b")
        dyn = DynamicCompositeAgent("dynamic-close", a, b)
        Agent.on_start(dyn)

        err = nothing
        try
            Agent.on_close(dyn)
        catch e
            err = e
        end

        @test err isa Base.CompositeException
        @test length(err.exceptions) == 2
        @test status(dyn) == Agent.CLOSED
    end
end
