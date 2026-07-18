using Test
using Agent

@testset "AgentInvoker Tests" begin
    mutable struct InvokerAgent
        work_count::Int
        started::Bool
        closed::Bool
        max_work::Int
    end

    InvokerAgent(max_work::Int=3) = InvokerAgent(0, false, false, max_work)
    Agent.name(::InvokerAgent) = "invoker"
    Agent.on_start(agent::InvokerAgent) = (agent.started = true)
    Agent.on_close(agent::InvokerAgent) = (agent.closed = true)
    function Agent.do_work(agent::InvokerAgent)
        agent.work_count += 1
        agent.work_count >= agent.max_work && throw(AgentTerminationException())
        return 1
    end

    @testset "Checked Lifecycle" begin
        owned_agent = InvokerAgent()
        invoker = AgentInvoker(owned_agent)

        @test agent(invoker) === owned_agent
        @test !is_started(invoker)
        @test !is_running(invoker)
        @test !is_closed(invoker)
        @test Agent.invoke(invoker) == 0

        start(invoker)
        start(invoker)
        @test is_started(invoker)
        @test is_running(invoker)
        @test owned_agent.started

        @test Agent.invoke(invoker) == 1
        @test Agent.invoke(invoker) == 1
        @test Agent.invoke(invoker) == 0

        @test is_closed(invoker)
        @test !is_running(invoker)
        @test owned_agent.closed
        @test Agent.invoke(invoker) == 0
        close(invoker)
    end

    @testset "Handled Work Error Continues" begin
        mutable struct RecoveringInvokerAgent
            calls::Int
            events::Vector{Symbol}
            closed::Bool
        end

        Agent.name(::RecoveringInvokerAgent) = "recovering-invoker"
        Agent.on_error(agent::RecoveringInvokerAgent, _) = push!(agent.events, :on_error)
        Agent.on_close(agent::RecoveringInvokerAgent) = (agent.closed = true)
        function Agent.do_work(agent::RecoveringInvokerAgent)
            agent.calls += 1
            agent.calls == 1 && error("recoverable")
            agent.calls == 3 && throw(AgentTerminationException())
            return 1
        end

        owned_agent = RecoveringInvokerAgent(0, Symbol[], false)
        counter = Threads.Atomic{Int}(0)
        handler = (agent, _) -> push!(agent.events, :handler)
        invoker = AgentInvoker(owned_agent; error_handler=handler, error_counter=counter)
        start(invoker)

        @test Agent.invoke(invoker) == 0
        @test is_running(invoker)
        @test counter[] == 1
        @test owned_agent.events == [:handler, :on_error]
        @test Agent.invoke(invoker) == 1
        @test Agent.invoke(invoker) == 0
        @test is_closed(invoker)
        @test owned_agent.closed
    end

    @testset "Unchecked Invocation" begin
        mutable struct UncheckedAgent
            calls::Int
            errors::Int
        end

        Agent.name(::UncheckedAgent) = "unchecked"
        Agent.do_work(agent::UncheckedAgent) = begin
            agent.calls += 1
            error("unchecked failure")
        end
        Agent.on_error(agent::UncheckedAgent, _) = (agent.errors += 1)

        owned_agent = UncheckedAgent(0, 0)
        invoker = AgentInvoker(owned_agent)
        start(invoker)
        exception = try
            invoke_unchecked(invoker)
            nothing
        catch e
            e
        end
        @test exception isa ErrorException
        @test is_running(invoker)

        handle_error(invoker, exception)
        @test owned_agent.errors == 1
        @test is_running(invoker)
        close(invoker)
    end

    @testset "Unexpected Termination Is Reported Without Counting" begin
        mutable struct UnexpectedInvokerAgent
            events::Vector{Symbol}
            closed::Bool
        end

        Agent.name(::UnexpectedInvokerAgent) = "unexpected"
        Agent.do_work(::UnexpectedInvokerAgent) = throw(AgentTerminationException(false))
        Agent.on_error(agent::UnexpectedInvokerAgent, _) = push!(agent.events, :on_error)
        Agent.on_close(agent::UnexpectedInvokerAgent) = (agent.closed = true)

        owned_agent = UnexpectedInvokerAgent(Symbol[], false)
        counter = Threads.Atomic{Int}(0)
        handler = (agent, _) -> push!(agent.events, :handler)
        invoker = AgentInvoker(owned_agent; error_handler=handler, error_counter=counter)
        start(invoker)

        @test Agent.invoke(invoker) == 0
        @test owned_agent.events == [:handler, :on_error]
        @test counter[] == 0
        @test is_closed(invoker)
        @test owned_agent.closed
    end

    @testset "Reporter Can Request Termination" begin
        mutable struct ReporterStopAgent
            closed::Bool
        end

        Agent.name(::ReporterStopAgent) = "reporter-stop"
        Agent.do_work(::ReporterStopAgent) = error("stop through reporter")
        Agent.on_close(agent::ReporterStopAgent) = (agent.closed = true)

        owned_agent = ReporterStopAgent(false)
        handler = (_, _) -> throw(AgentTerminationException())
        invoker = AgentInvoker(owned_agent; error_handler=handler)
        start(invoker)

        @test Agent.invoke(invoker) == 0
        @test is_closed(invoker)
        @test owned_agent.closed
    end

    @testset "Lifecycle Errors Do Not Increment Counter" begin
        mutable struct StartupFailureInvokerAgent
            events::Vector{Symbol}
            closed::Bool
        end

        Agent.name(::StartupFailureInvokerAgent) = "startup-failure"
        Agent.on_start(::StartupFailureInvokerAgent) = error("startup failure")
        Agent.on_error(agent::StartupFailureInvokerAgent, _) = push!(agent.events, :on_error)
        Agent.on_close(agent::StartupFailureInvokerAgent) = (agent.closed = true)
        Agent.do_work(::StartupFailureInvokerAgent) = 0

        owned_agent = StartupFailureInvokerAgent(Symbol[], false)
        counter = Threads.Atomic{Int}(0)
        handler = (agent, _) -> push!(agent.events, :handler)
        invoker = AgentInvoker(owned_agent; error_handler=handler, error_counter=counter)
        start(invoker)

        @test is_started(invoker)
        @test is_closed(invoker)
        @test owned_agent.closed
        @test owned_agent.events == [:handler, :on_error]
        @test counter[] == 0
    end

    @testset "Counter Must Be Atomic" begin
        @test_throws ArgumentError AgentInvoker(InvokerAgent(); error_counter=Ref(0))
    end
end
