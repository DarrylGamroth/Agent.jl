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

        @test fetch(Threads.@spawn try_add(dyn, b))
        @test !has_add_completed(dyn)
        @test !try_add(dyn, DynAgent("pending"))

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
        @test_throws ArgumentError has_add_completed(dyn)
        @test_throws ArgumentError has_remove_completed(dyn)
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

    @testset "Work Cursor Resumes After Failure" begin
        mutable struct DynamicCursorAgent
            name::String
            calls::Int
            should_fail::Bool
        end

        Agent.name(agent::DynamicCursorAgent) = agent.name
        Agent.do_work(agent::DynamicCursorAgent) = begin
            agent.calls += 1
            agent.should_fail && error("$(agent.name) failed")
            1
        end

        first_agent = DynamicCursorAgent("first", 0, true)
        later_agent = DynamicCursorAgent("later", 0, false)
        composite = DynamicCompositeAgent("cursor", first_agent, later_agent)
        Agent.on_start(composite)

        @test_throws ErrorException Agent.do_work(composite)
        @test (first_agent.calls, later_agent.calls) == (1, 0)
        @test Agent.do_work(composite) == 1
        @test (first_agent.calls, later_agent.calls) == (1, 1)

        @test_throws ErrorException Agent.do_work(composite)
        @test Agent.do_work(composite) == 1
        @test (first_agent.calls, later_agent.calls) == (2, 2)

        Agent.on_close(composite)
    end

    @testset "Failed Add Preserves Pending Removal" begin
        mutable struct FailingAddAgent
            closed::Bool
        end

        Agent.name(::FailingAddAgent) = "failing-add"
        Agent.on_start(::FailingAddAgent) = error("add startup failure")
        Agent.on_close(agent::FailingAddAgent) = (agent.closed = true)
        Agent.do_work(::FailingAddAgent) = 0

        existing = DynAgent("existing")
        failing = FailingAddAgent(false)
        composite = DynamicCompositeAgent("request-order", existing)
        Agent.on_start(composite)

        @test try_add(composite, failing)
        @test try_remove(composite, existing)
        @test_throws ErrorException Agent.do_work(composite)
        @test failing.closed
        @test has_add_completed(composite)
        @test !has_remove_completed(composite)

        @test Agent.do_work(composite) == 0
        @test has_remove_completed(composite)
        @test existing.closed
        Agent.on_close(composite)
    end

    @testset "Cross-Thread Request Publication" begin
        mutable struct PublishedAgent
            id::Int
            started::Threads.Atomic{Bool}
            closed::Threads.Atomic{Bool}
        end

        PublishedAgent(id::Int) = PublishedAgent(
            id,
            Threads.Atomic{Bool}(false),
            Threads.Atomic{Bool}(false),
        )
        Agent.name(agent::PublishedAgent) = "published-$(agent.id)"
        Agent.on_start(agent::PublishedAgent) = (agent.started[] = true)
        Agent.on_close(agent::PublishedAgent) = (agent.closed[] = true)
        Agent.do_work(::PublishedAgent) = 0

        composite = DynamicCompositeAgent("publication")
        runner = AgentRunner(NoOpIdleStrategy(), composite)
        if Agent.managed_thread_count() == 1
            start(runner)
        else
            start_on_thread(runner, Agent.managed_thread_count())
        end
        @test timedwait(
            () -> status(composite) === Agent.ACTIVE,
            5.0;
            pollint=0.001,
        ) === :ok

        for id in 1:64
            sub_agent = PublishedAgent(id)
            @test try_add(composite, sub_agent)
            @test timedwait(
                () -> has_add_completed(composite),
                5.0;
                pollint=0.001,
            ) === :ok
            @test timedwait(() -> sub_agent.started[], 5.0; pollint=0.001) === :ok

            @test try_remove(composite, sub_agent)
            @test timedwait(
                () -> has_remove_completed(composite),
                5.0;
                pollint=0.001,
            ) === :ok
            @test timedwait(() -> sub_agent.closed[], 5.0; pollint=0.001) === :ok
        end

        @test request_stop!(runner)
        wait(runner)
        @test status(composite) === Agent.CLOSED
    end
end
