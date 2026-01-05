using Test
using Agent

@testset "CompositeAgent Tests" begin
    mutable struct SubAgent
        name::String
        started::Bool
        closed::Bool
        work_count::Int
    end

    SubAgent(name::String) = SubAgent(name, false, false, 0)

    Agent.name(agent::SubAgent) = agent.name
    Agent.on_start(agent::SubAgent) = (agent.started = true)
    Agent.on_close(agent::SubAgent) = (agent.closed = true)

    function Agent.do_work(agent::SubAgent)
        agent.work_count += 1
        return 1
    end

    @testset "Lifecycle and Work" begin
        a = SubAgent("a")
        b = SubAgent("b")
        composite = CompositeAgent(a, b)

        @test Agent.name(composite) == "[a,b]"

        Agent.on_start(composite)
        @test a.started
        @test b.started

        work = Agent.do_work(composite)
        @test work == 2
        @test a.work_count == 1
        @test b.work_count == 1

        Agent.on_close(composite)
        @test a.closed
        @test b.closed
    end

    @testset "Start Errors Collected" begin
        mutable struct ErrorStartAgent
            name::String
            started::Bool
        end

        ErrorStartAgent(name::String) = ErrorStartAgent(name, false)

        Agent.name(agent::ErrorStartAgent) = agent.name
        function Agent.on_start(agent::ErrorStartAgent)
            agent.started = true
            error("start error")
        end
        Agent.do_work(agent::ErrorStartAgent) = 0

        a = ErrorStartAgent("a")
        b = ErrorStartAgent("b")
        composite = CompositeAgent(a, b)

        err = nothing
        try
            Agent.on_start(composite)
        catch e
            err = e
        end

        @test err isa Base.CompositeException
        @test length(err.exceptions) == 2
        @test a.started
        @test b.started
    end
end
