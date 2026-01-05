using Test
using Agent

@testset "AgentInvoker Tests" begin
    mutable struct InvokerAgent
        name::String
        work_count::Int
        started::Bool
        closed::Bool
        max_work::Int
    end

    InvokerAgent(name::String, max_work::Int=3) = InvokerAgent(name, 0, false, false, max_work)

    Agent.name(agent::InvokerAgent) = agent.name
    Agent.on_start(agent::InvokerAgent) = (agent.started = true)
    Agent.on_close(agent::InvokerAgent) = (agent.closed = true)

    function Agent.do_work(agent::InvokerAgent)
        agent.work_count += 1
        if agent.work_count >= agent.max_work
            throw(AgentTerminationException())
        end
        return 1
    end

    @testset "Lifecycle" begin
        agent = InvokerAgent("invoker")
        invoker = AgentInvoker(agent)

        start(invoker)
        @test is_started(invoker)
        @test is_running(invoker)
        @test agent.started

        while is_running(invoker)
            Agent.invoke(invoker)
        end

        @test is_closed(invoker)
        @test agent.closed
        @test agent.work_count >= agent.max_work
    end

    @testset "Error Handling Order" begin
        mutable struct ErrorInvokerAgent
            events::Vector{Symbol}
            work_count::Int
        end

        ErrorInvokerAgent() = ErrorInvokerAgent(Symbol[], 0)

        Agent.name(agent::ErrorInvokerAgent) = "error-invoker"
        Agent.on_error(agent::ErrorInvokerAgent, error) = push!(agent.events, :on_error)

        function Agent.do_work(agent::ErrorInvokerAgent)
            agent.work_count += 1
            if agent.work_count == 1
                error("invoker error")
            end
            throw(AgentTerminationException())
        end

        agent = ErrorInvokerAgent()
        handler = (agent, error) -> push!(agent.events, :error_handler)
        invoker = AgentInvoker(agent; error_handler=handler)

        start(invoker)
        Agent.invoke(invoker)

        @test agent.events[1] == :error_handler
        @test agent.events[2] == :on_error
        close(invoker)
    end
end
