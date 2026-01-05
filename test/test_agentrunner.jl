using Test
using Agent

@testset "AgentRunner Tests" begin
    
    # Simple test agent for runner tests
    mutable struct SimpleTestAgent
        name::String
        work_count::Int
        started::Bool
        closed::Bool
        error_occurred::Bool
        max_work::Int
    end
    
    SimpleTestAgent(name::String, max_work::Int=5) = SimpleTestAgent(name, 0, false, false, false, max_work)
    
    Agent.name(agent::SimpleTestAgent) = agent.name
    Agent.on_start(agent::SimpleTestAgent) = (agent.started = true)
    Agent.on_close(agent::SimpleTestAgent) = (agent.closed = true)
    Agent.on_error(agent::SimpleTestAgent, error) = (agent.error_occurred = true)
    
    function Agent.do_work(agent::SimpleTestAgent)
        agent.work_count += 1
        if agent.work_count >= agent.max_work
            throw(AgentTerminationException())
        end
        return 1  # Work was done
    end
    
    @testset "AgentRunner Construction" begin
        agent = SimpleTestAgent("test")
        idle_strategy = NoOpIdleStrategy()
        
        runner = AgentRunner(idle_strategy, agent)
        @test isa(runner, AgentRunner)
        @test runner.idle_strategy === idle_strategy
        @test runner.agent === agent
        @test !Agent.is_running(runner)
        @test !Agent.is_closed(runner)
        @test isopen(runner)
    end
    
    @testset "AgentRunner State Management" begin
        agent = SimpleTestAgent("test")
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test initial state
        @test !Agent.is_running(runner)
        @test !Agent.is_closed(runner)
        @test isopen(runner)
        
        # Test state setters
        Agent.is_running!(runner, true)
        @test Agent.is_running(runner)
        @test isready(runner)  # isready should return is_running
        
        Agent.is_running!(runner, false)
        @test !Agent.is_running(runner)
        @test !isready(runner)
        
        Agent.is_closed!(runner, true)
        @test Agent.is_closed(runner)
        @test !isopen(runner)
        
        Agent.is_closed!(runner, false)
        @test !Agent.is_closed(runner)
        @test isopen(runner)
    end
    
    @testset "AgentRunner Lifecycle" begin
        agent = SimpleTestAgent("lifecycle-test")
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test that agent hasn't started yet
        @test !agent.started
        @test !agent.closed
        
        # Start the runner
        start_on_thread(runner)
        @test runner.is_started
        
        # Wait a short time for agent to start and do some work
        sleep(0.1)
        
        # The agent should have started and be doing work
        @test agent.started
        @test agent.work_count > 0
        
        # Wait for agent to terminate itself (after max_work iterations)
        wait(runner)
        
        # Agent should be closed now
        @test agent.closed
        @test Agent.is_closed(runner)
        @test !isopen(runner)
        
        # Close should be idempotent
        close(runner)
        @test Agent.is_closed(runner)
    end

    @testset "AgentRunner Close Before Start" begin
        agent = SimpleTestAgent("close-before-start")
        runner = AgentRunner(NoOpIdleStrategy(), agent)

        close(runner)

        @test agent.closed
        @test Agent.is_closed(runner)
        @test_throws ArgumentError start_on_thread(runner)
    end
    
    @testset "AgentRunner Error Conditions" begin
        agent = SimpleTestAgent("error-test")
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test starting twice
        start_on_thread(runner)
        @test_throws ArgumentError start_on_thread(runner)
        
        # Clean up
        wait(runner)
        close(runner)
        
        # Test starting closed runner
        @test_throws ArgumentError start_on_thread(runner)
    end
    
    @testset "AgentRunner with Different Idle Strategies" begin
        strategies = [
            NoOpIdleStrategy(),
            BusySpinIdleStrategy(),
            YieldingIdleStrategy(),
            SleepingIdleStrategy(1000),  # 1 microsecond
            SleepingMillisIdleStrategy(1),  # 1 millisecond
            BackoffIdleStrategy()
        ]
        
        for (i, strategy) in enumerate(strategies)
            agent = SimpleTestAgent("strategy-test-$i", 3)  # Terminate after 3 iterations
            runner = AgentRunner(strategy, agent)
            
            @test isa(runner, AgentRunner)
            @test runner.idle_strategy === strategy
            
            # Start and run the agent
            start_on_thread(runner)
            wait(runner)
            
            # Verify agent lifecycle was called
            @test agent.started
            @test agent.closed
            @test agent.work_count >= 3
            @test Agent.is_closed(runner)
            
            close(runner)
        end
    end
    
    @testset "AgentRunner Thread Assignment" begin
        agent = SimpleTestAgent("thread-test", 2)
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test default thread assignment (no specific thread)
        start_on_thread(runner)
        wait(runner)
        
        @test agent.started
        @test agent.closed
        @test Agent.is_closed(runner)
        
        close(runner)
        
        # Test specific thread assignment (if multiple threads available)
        if Threads.nthreads() > 1
            agent2 = SimpleTestAgent("thread-test-2", 2)
            runner2 = AgentRunner(NoOpIdleStrategy(), agent2)
            
            start_on_thread(runner2, 2)  # Try to run on thread 2
            wait(runner2)
            
            @test agent2.started
            @test agent2.closed
            @test Agent.is_closed(runner2)
            
            close(runner2)
        else
            # Test thread assignment on single thread system
            agent2 = SimpleTestAgent("thread-test-single", 2)
            runner2 = AgentRunner(NoOpIdleStrategy(), agent2)
            
            # This should still work on single-threaded systems
            start_on_thread(runner2, 1)
            wait(runner2)
            
            @test agent2.started
            @test agent2.closed
            @test Agent.is_closed(runner2)
            
            close(runner2)
        end
    end
    
    @testset "AgentRunner Error Handling" begin
        # Agent that throws errors
        mutable struct ErrorHandlingAgent
            work_count::Int
            should_error::Bool
            error_handled::Bool
            events::Vector{Symbol}
        end
        
        ErrorHandlingAgent() = ErrorHandlingAgent(0, false, false, Symbol[])
        
        Agent.name(agent::ErrorHandlingAgent) = "error-agent"
        Agent.on_error(agent::ErrorHandlingAgent, error) = (agent.error_handled = true; push!(agent.events, :on_error))
        
        function Agent.do_work(agent::ErrorHandlingAgent)
            agent.work_count += 1
            if agent.should_error && agent.work_count == 2
                error("Test error")
            elseif agent.work_count >= 5
                throw(AgentTerminationException())
            end
            return 1
        end
        
        # Test error handling
        agent = ErrorHandlingAgent()
        agent.should_error = true
        handler = (agent, error) -> push!(agent.events, :error_handler)
        runner = AgentRunner(NoOpIdleStrategy(), agent; error_handler=handler)
        
        start_on_thread(runner)
        wait(runner)
        
        @test agent.error_handled
        @test agent.events[1] == :error_handler
        @test agent.events[2] == :on_error
        @test Agent.is_closed(runner)
        
        close(runner)
    end

    @testset "AgentRunner Error Counter and Handler Termination" begin
        mutable struct CounterAgent
            name::String
            work_count::Int
            events::Vector{Symbol}
        end

        CounterAgent(name::String) = CounterAgent(name, 0, Symbol[])

        Agent.name(agent::CounterAgent) = agent.name
        Agent.on_error(agent::CounterAgent, error) = push!(agent.events, :on_error)

        function Agent.do_work(agent::CounterAgent)
            agent.work_count += 1
            error("boom")
        end

        agent = CounterAgent("counter-agent")
        counter = Ref(0)
        handler = (agent, error) -> (push!(agent.events, :error_handler); throw(AgentTerminationException()))
        runner = AgentRunner(NoOpIdleStrategy(), agent; error_handler=handler, error_counter=counter)

        start_on_thread(runner)
        wait(runner)

        @test counter[] == 1
        @test agent.events == [:error_handler]
        @test Agent.is_closed(runner)

        close(runner)
    end
    
    @testset "AgentRunner Interrupt Handling" begin
        # Long-running agent for interrupt testing
        mutable struct LongRunningAgent
            work_count::Int
            started::Bool
            closed::Bool
        end
        
        LongRunningAgent() = LongRunningAgent(0, false, false)
        
        Agent.name(agent::LongRunningAgent) = "long-running"
        Agent.on_start(agent::LongRunningAgent) = (agent.started = true)
        Agent.on_close(agent::LongRunningAgent) = (agent.closed = true)
        
        function Agent.do_work(agent::LongRunningAgent)
            agent.work_count += 1
            sleep(0.01)  # Simulate work
            return 1
        end
        
        agent = LongRunningAgent()
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        start_on_thread(runner)
        
        # Let it run briefly
        sleep(0.05)
        @test agent.started
        @test agent.work_count > 0
        @test Agent.is_running(runner)
        
        # Interrupt by closing
        close(runner)
        
        @test agent.closed
        @test Agent.is_closed(runner)
        @test !Agent.is_running(runner)
    end
end
