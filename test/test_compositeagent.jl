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

    @testset "Heterogeneous Agents" begin
        mutable struct SubAgentA
            name::String
            work_count::Int
        end

        mutable struct SubAgentB
            name::String
            work_count::Int
        end

        SubAgentA(name::String) = SubAgentA(name, 0)
        SubAgentB(name::String) = SubAgentB(name, 0)

        Agent.name(agent::SubAgentA) = agent.name
        Agent.name(agent::SubAgentB) = agent.name
        Agent.on_start(agent::SubAgentA) = nothing
        Agent.on_start(agent::SubAgentB) = nothing
        Agent.on_close(agent::SubAgentA) = nothing
        Agent.on_close(agent::SubAgentB) = nothing
        Agent.do_work(agent::SubAgentA) = (agent.work_count += 1; 1)
        Agent.do_work(agent::SubAgentB) = (agent.work_count += 1; 2)

        a = SubAgentA("a")
        b = SubAgentB("b")
        composite = CompositeAgent(a, b)

        # Warm up JIT before allocation assertions.
        Agent.do_work(composite)
        Agent.on_start(composite)
        Agent.on_close(composite)

        @test Agent.do_work(composite) == 3
        @test a.work_count == 2
        @test b.work_count == 2

        # The repeated duty cycle is the allocation-sensitive hot path.
        # Lifecycle aggregation intentionally creates an error collection.
        # Coverage instrumentation itself can allocate in otherwise
        # allocation-free calls, so assert only in uninstrumented runs.
        if Base.JLOptions().code_coverage == 0
            @test @allocated(Agent.do_work(composite)) == 0
        end
    end

    @testset "Work Cursor Resumes After Failure" begin
        mutable struct CursorAgent
            name::String
            calls::Int
            should_fail::Bool
        end

        Agent.name(agent::CursorAgent) = agent.name
        function Agent.do_work(agent::CursorAgent)
            agent.calls += 1
            agent.should_fail && error("$(agent.name) failed")
            return 1
        end

        first_agent = CursorAgent("first", 0, true)
        later_agent = CursorAgent("later", 0, false)
        composite = CompositeAgent(first_agent, later_agent)

        @test_throws ErrorException Agent.do_work(composite)
        @test (first_agent.calls, later_agent.calls) == (1, 0)

        # Agrona advances the cursor before invocation, so the later agent is
        # serviced on the next duty cycle instead of being starved.
        @test Agent.do_work(composite) == 1
        @test (first_agent.calls, later_agent.calls) == (1, 1)

        @test_throws ErrorException Agent.do_work(composite)
        @test Agent.do_work(composite) == 1
        @test (first_agent.calls, later_agent.calls) == (2, 2)
    end
end
