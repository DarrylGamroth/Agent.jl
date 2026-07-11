using Test
using Agent
using StableTasks

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
        @test !is_started(runner)
        @test !Agent.is_running(runner)
        @test !Agent.is_closed(runner)
        @test isopen(runner)
    end
    
    @testset "AgentRunner State Observation" begin
        agent = SimpleTestAgent("test")
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test initial state
        @test !is_started(runner)
        @test !Agent.is_running(runner)
        @test !Agent.is_closed(runner)
        @test isopen(runner)
        @test !isready(runner)
    end
    
    @testset "AgentRunner Lifecycle" begin
        agent = SimpleTestAgent("lifecycle-test")
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        # Test that agent hasn't started yet
        @test !agent.started
        @test !agent.closed
        
        # Start the runner
        start_on_thread(runner)
        @test is_started(runner)
        
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
        
        # Test specific assignment to the last managed Julia thread. With an
        # interactive pool this id is greater than Threads.nthreads().
        if Agent.managed_thread_count() > 1
            mutable struct ThreadRecordingAgent
                threadid::Int
            end
            Agent.do_work(agent::ThreadRecordingAgent) =
                (agent.threadid = Threads.threadid(); throw(AgentTerminationException()))

            agent2 = ThreadRecordingAgent(0)
            runner2 = AgentRunner(NoOpIdleStrategy(), agent2)
            target_thread = Agent.managed_thread_count()
            
            start_on_thread(runner2, target_thread)
            wait(runner2)
            
            @test agent2.threadid == target_thread
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

        invalid_thread = Agent.managed_thread_count() + 1
        invalid_runner = AgentRunner(NoOpIdleStrategy(), SimpleTestAgent("invalid-thread", 2))
        @test_throws ArgumentError start_on_thread(invalid_runner, invalid_thread)
        close(invalid_runner)
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
        
        # Cooperative shutdown waits for the current duty cycle to finish.
        close(runner)
        
        @test agent.closed
        @test Agent.is_closed(runner)
        @test !Agent.is_running(runner)
    end

    @testset "AgentRunner Fatal Failure Propagation" begin
        mutable struct FatalAgent
            closed::Bool
        end

        Agent.do_work(::FatalAgent) = error("fatal work failure")
        Agent.on_close(agent::FatalAgent) = (agent.closed = true)

        agent = FatalAgent(false)
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        start_on_thread(runner)

        @test_throws TaskFailedException wait(runner)
        @test istaskfailed(runner.task)
        @test agent.closed
        @test Agent.is_closed(runner)
        close(runner)
    end

    @testset "AgentRunner Cleanup Failure Closes Runner" begin
        mutable struct CleanupFailureAgent
            fail_close::Bool
        end

        Agent.do_work(::CleanupFailureAgent) = throw(AgentTerminationException())
        function Agent.on_close(agent::CleanupFailureAgent)
            agent.fail_close && error("cleanup failure")
            return nothing
        end

        agent = CleanupFailureAgent(true)
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        task = start_on_thread(runner)

        @test task isa StableTasks.StableTask
        @test_throws TaskFailedException wait(runner)
        @test Agent.is_closed(runner)
        @test !isopen(runner)
        close(runner)

        before_start = AgentRunner(NoOpIdleStrategy(), CleanupFailureAgent(true))
        @test_throws ErrorException close(before_start)
        @test Agent.is_closed(before_start)
    end

    @testset "AgentRunner Close Wins Startup Race" begin
        mutable struct StartupRaceAgent
            close_entered::Channel{Nothing}
            close_release::Channel{Nothing}
            starts::Int
            work::Int
            closes::Int
        end

        Agent.on_start(agent::StartupRaceAgent) = (agent.starts += 1)
        Agent.do_work(agent::StartupRaceAgent) = (agent.work += 1; 0)
        function Agent.on_close(agent::StartupRaceAgent)
            agent.closes += 1
            put!(agent.close_entered, nothing)
            take!(agent.close_release)
            return nothing
        end

        agent = StartupRaceAgent(Channel{Nothing}(1), Channel{Nothing}(1), 0, 0, 0)
        runner = AgentRunner(YieldingIdleStrategy(), agent)
        closer = Threads.@spawn close(runner)

        take!(agent.close_entered)
        @test_throws ArgumentError start_on_thread(runner)
        put!(agent.close_release, nothing)
        wait(closer)

        @test agent.starts == 0
        @test agent.work == 0
        @test agent.closes == 1
        @test !is_started(runner)
        @test Agent.is_closed(runner)
    end

    @testset "AgentRunner Close Before Task Claim" begin
        mutable struct UnclaimedAgent
            starts::Int
            work::Int
            closes::Int
        end

        Agent.on_start(agent::UnclaimedAgent) = (agent.starts += 1)
        Agent.do_work(agent::UnclaimedAgent) = (agent.work += 1; 0)
        Agent.on_close(agent::UnclaimedAgent) = (agent.closes += 1)

        agent = UnclaimedAgent(0, 0, 0)
        runner = AgentRunner(YieldingIdleStrategy(), agent)
        start_on_thread(runner, Threads.threadid())
        close(runner)

        @test agent.starts == 0
        @test agent.work == 0
        @test agent.closes == 1
        @test istaskdone(runner.task)
        @test Agent.is_closed(runner)
    end

    @testset "AgentRunner Concurrent Close" begin
        mutable struct ConcurrentCloseAgent
            started::Channel{Nothing}
            closes::Int
        end

        Agent.on_start(agent::ConcurrentCloseAgent) = put!(agent.started, nothing)
        Agent.do_work(::ConcurrentCloseAgent) = (sleep(0.01); 0)
        Agent.on_close(agent::ConcurrentCloseAgent) = (agent.closes += 1)

        agent = ConcurrentCloseAgent(Channel{Nothing}(1), 0)
        runner = AgentRunner(YieldingIdleStrategy(), agent)
        start_on_thread(runner)
        take!(agent.started)

        closers = ntuple(_ -> Threads.@spawn(close(runner)), 3)
        foreach(wait, closers)

        @test agent.closes == 1
        @test Agent.is_closed(runner)
        @test istaskdone(runner.task)
    end

    @testset "AgentRunner Thread-Count Specialization" begin
        runner = AgentRunner(NoOpIdleStrategy(), SimpleTestAgent("specialization", 2))
        @test typeof(runner).parameters[5] == Agent.managed_thread_count()

        method = which(Agent.run_loop, (typeof(runner),))
        if Agent.managed_thread_count() == 1
            @test occursin("AgentRunner{I, A, H, C, 1}", string(method.sig))
        else
            @test method.sig == Tuple{typeof(Agent.run_loop), AgentRunner}
        end

        close(runner)
    end
end
