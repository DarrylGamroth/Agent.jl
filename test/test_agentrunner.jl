using Test
using Agent
using StableTasks

@testset "AgentRunner Tests" begin
    mutable struct FiniteRunnerAgent
        work_count::Int
        started::Bool
        closed::Bool
        max_work::Int
    end

    FiniteRunnerAgent(max_work::Int=3) = FiniteRunnerAgent(0, false, false, max_work)
    Agent.name(::FiniteRunnerAgent) = "finite-runner"
    Agent.on_start(agent::FiniteRunnerAgent) = (agent.started = true)
    Agent.on_close(agent::FiniteRunnerAgent) = (agent.closed = true)
    function Agent.do_work(agent::FiniteRunnerAgent)
        agent.work_count += 1
        agent.work_count >= agent.max_work && throw(AgentTerminationException())
        return 1
    end

    @testset "Construction and Observation" begin
        owned_agent = FiniteRunnerAgent()
        strategy = NoOpIdleStrategy()
        runner = AgentRunner(strategy, owned_agent)

        @test runner.idle_strategy === strategy
        @test agent(runner) === owned_agent
        @test runner_task(runner) === nothing
        @test !is_started(runner)
        @test !is_running(runner)
        @test !is_closed(runner)
        @test isopen(runner)
        @test !isready(runner)
        @test !request_stop!(runner)
        @test_throws ArgumentError AgentRunner(strategy, owned_agent; error_counter=Ref(0))
    end

    @testset "Scheduler-Managed Lifecycle" begin
        owned_agent = FiniteRunnerAgent()
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
        task = start(runner)

        @test task isa StableTasks.StableTask
        @test runner_task(runner) === task
        @test !task.t.sticky
        @test is_started(runner)
        @test_throws ArgumentError start(runner)

        wait(runner)
        @test owned_agent.started
        @test owned_agent.closed
        @test owned_agent.work_count == owned_agent.max_work
        @test is_closed(runner)
        @test !isopen(runner)
        @test isready(runner)
        close(runner)
    end

    @testset "No-Argument Compatibility Alias" begin
        runner = AgentRunner(NoOpIdleStrategy(), FiniteRunnerAgent(1))
        task = start_on_thread(runner)
        @test !task.t.sticky
        wait(runner)
    end

    @testset "Close Before Start" begin
        owned_agent = FiniteRunnerAgent()
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)

        close(runner)
        @test owned_agent.closed
        @test !owned_agent.started
        @test is_closed(runner)
        @test !is_started(runner)
        @test_throws ArgumentError start(runner)
        @test_throws ArgumentError start_on_thread(runner, 1)
    end

    @testset "Idle Strategies" begin
        strategies = (
            NoOpIdleStrategy(),
            BusySpinIdleStrategy(),
            YieldingIdleStrategy(),
            SleepingIdleStrategy(),
            SleepingMillisIdleStrategy(),
            BackoffIdleStrategy(),
            ControllableIdleStrategy(CONTROLLABLE_NOOP),
        )

        for strategy in strategies
            owned_agent = FiniteRunnerAgent(3)
            runner = AgentRunner(strategy, owned_agent)
            start(runner)
            wait(runner)
            @test owned_agent.started
            @test owned_agent.closed
            @test owned_agent.work_count == 3
            @test is_closed(runner)
        end
    end

    @testset "Explicit Julia Thread Assignment" begin
        mutable struct ThreadRecordingRunnerAgent
            threadid::Int
        end

        Agent.name(::ThreadRecordingRunnerAgent) = "thread-recording"
        Agent.do_work(agent::ThreadRecordingRunnerAgent) = begin
            agent.threadid = Threads.threadid()
            throw(AgentTerminationException())
        end

        target_thread = Agent.managed_thread_count()
        owned_agent = ThreadRecordingRunnerAgent(0)
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
        task = start_on_thread(runner, target_thread)
        @test task.t.sticky
        wait(runner)
        @test owned_agent.threadid == target_thread

        invalid_thread = Agent.managed_thread_count() + 1
        invalid_runner = AgentRunner(NoOpIdleStrategy(), FiniteRunnerAgent(1))
        @test_throws ArgumentError start_on_thread(invalid_runner, invalid_thread)
        @test_throws ArgumentError start_on_thread(invalid_runner, 0)
        close(invalid_runner)
    end

    @testset "Handled Work Errors Continue" begin
        mutable struct RecoveringRunnerAgent
            calls::Int
            events::Vector{Symbol}
            closed::Bool
        end

        Agent.name(::RecoveringRunnerAgent) = "recovering-runner"
        Agent.on_error(agent::RecoveringRunnerAgent, _) = push!(agent.events, :on_error)
        Agent.on_close(agent::RecoveringRunnerAgent) = (agent.closed = true)
        function Agent.do_work(agent::RecoveringRunnerAgent)
            agent.calls += 1
            agent.calls == 1 && error("recoverable")
            agent.calls == 3 && throw(AgentTerminationException())
            return 1
        end

        owned_agent = RecoveringRunnerAgent(0, Symbol[], false)
        counter = Threads.Atomic{Int}(0)
        handler = (agent, _) -> push!(agent.events, :handler)
        runner = AgentRunner(
            NoOpIdleStrategy(),
            owned_agent;
            error_handler=handler,
            error_counter=counter,
        )
        start(runner)
        wait(runner)

        @test owned_agent.calls == 3
        @test owned_agent.events == [:handler, :on_error]
        @test counter[] == 1
        @test owned_agent.closed
    end

    @testset "Reporter Can Request Stop" begin
        mutable struct ReporterStopRunnerAgent
            closed::Bool
        end

        Agent.name(::ReporterStopRunnerAgent) = "reporter-stop-runner"
        Agent.do_work(::ReporterStopRunnerAgent) = error("stop")
        Agent.on_close(agent::ReporterStopRunnerAgent) = (agent.closed = true)

        owned_agent = ReporterStopRunnerAgent(false)
        counter = Threads.Atomic{Int}(0)
        handler = (_, _) -> throw(AgentTerminationException())
        runner = AgentRunner(
            NoOpIdleStrategy(),
            owned_agent;
            error_handler=handler,
            error_counter=counter,
        )
        start(runner)
        wait(runner)

        @test counter[] == 1
        @test owned_agent.closed
        @test is_closed(runner)
    end

    @testset "Expected and Unexpected Termination" begin
        mutable struct TerminationRunnerAgent
            expected::Bool
            events::Vector{Symbol}
        end

        Agent.name(::TerminationRunnerAgent) = "termination-runner"
        Agent.do_work(agent::TerminationRunnerAgent) =
            throw(AgentTerminationException(agent.expected))
        Agent.on_error(agent::TerminationRunnerAgent, _) = push!(agent.events, :on_error)

        for expected in (true, false)
            owned_agent = TerminationRunnerAgent(expected, Symbol[])
            counter = Threads.Atomic{Int}(0)
            handler = (agent, _) -> push!(agent.events, :handler)
            runner = AgentRunner(
                NoOpIdleStrategy(),
                owned_agent;
                error_handler=handler,
                error_counter=counter,
            )
            start(runner)
            wait(runner)

            @test owned_agent.events == (expected ? Symbol[] : [:handler, :on_error])
            @test counter[] == 0
            @test is_closed(runner)
        end
    end

    @testset "Fatal Failure Propagation" begin
        mutable struct FatalRunnerAgent
            closed::Bool
        end

        Agent.name(::FatalRunnerAgent) = "fatal-runner"
        Agent.do_work(::FatalRunnerAgent) = error("fatal work failure")
        Agent.on_close(agent::FatalRunnerAgent) = (agent.closed = true)

        owned_agent = FatalRunnerAgent(false)
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
        start(runner)

        @test_throws TaskFailedException wait(runner)
        @test istaskfailed(runner_task(runner))
        @test owned_agent.closed
        @test is_closed(runner)
        close(runner)
    end

    @testset "Startup Failure Cleans Up and Does Not Count" begin
        mutable struct StartupFailureRunnerAgent
            closed::Bool
        end

        Agent.name(::StartupFailureRunnerAgent) = "startup-failure-runner"
        Agent.on_start(::StartupFailureRunnerAgent) = error("startup failure")
        Agent.on_close(agent::StartupFailureRunnerAgent) = (agent.closed = true)
        Agent.do_work(::StartupFailureRunnerAgent) = 0

        owned_agent = StartupFailureRunnerAgent(false)
        counter = Threads.Atomic{Int}(0)
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent; error_counter=counter)
        start(runner)

        @test_throws TaskFailedException wait(runner)
        @test counter[] == 0
        @test owned_agent.closed
        @test is_closed(runner)
    end

    @testset "Cleanup Failure Still Closes" begin
        mutable struct CleanupFailureRunnerAgent
            fail_close::Bool
        end

        Agent.name(::CleanupFailureRunnerAgent) = "cleanup-failure-runner"
        Agent.do_work(::CleanupFailureRunnerAgent) = throw(AgentTerminationException())
        Agent.on_close(agent::CleanupFailureRunnerAgent) =
            agent.fail_close ? error("cleanup failure") : nothing

        runner = AgentRunner(NoOpIdleStrategy(), CleanupFailureRunnerAgent(true))
        start(runner)
        @test_throws TaskFailedException wait(runner)
        @test is_closed(runner)
        @test !isopen(runner)

        through_close = AgentRunner(
            NoOpIdleStrategy(),
            CleanupFailureRunnerAgent(true),
        )
        start_on_thread(through_close, Threads.threadid())
        @test_throws TaskFailedException close(through_close)
        @test is_closed(through_close)
        @test !isopen(through_close)

        before_start = AgentRunner(NoOpIdleStrategy(), CleanupFailureRunnerAgent(true))
        @test_throws ErrorException close(before_start)
        @test is_closed(before_start)
        @test !isopen(before_start)
    end

    @testset "Non-Blocking Stop Request" begin
        mutable struct StopRequestRunnerAgent
            started::Channel{Nothing}
            closed::Bool
        end

        Agent.name(::StopRequestRunnerAgent) = "stop-request-runner"
        Agent.on_start(agent::StopRequestRunnerAgent) = put!(agent.started, nothing)
        Agent.do_work(::StopRequestRunnerAgent) = 0
        Agent.on_close(agent::StopRequestRunnerAgent) = (agent.closed = true)

        owned_agent = StopRequestRunnerAgent(Channel{Nothing}(1), false)
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
        start(runner)
        take!(owned_agent.started)

        @test request_stop!(runner)
        @test !request_stop!(runner)
        wait(runner)
        @test owned_agent.closed
        @test is_closed(runner)
    end

    @testset "Shutdown Stall Diagnostics" begin
        mutable struct BlockingRunnerAgent
            entered::Channel{Nothing}
            release::Channel{Nothing}
            closed::Bool
        end

        Agent.name(::BlockingRunnerAgent) = "blocking-runner"
        Agent.do_work(agent::BlockingRunnerAgent) = begin
            put!(agent.entered, nothing)
            take!(agent.release)
            0
        end
        Agent.on_close(agent::BlockingRunnerAgent) = (agent.closed = true)

        owned_agent = BlockingRunnerAgent(
            Channel{Nothing}(1),
            Channel{Nothing}(1),
            false,
        )
        runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
        start(runner)
        take!(owned_agent.entered)

        stalls = Threads.Atomic{Int}(0)
        close(runner, 0.01; on_stall = stalled_runner -> begin
            @test stalled_runner === runner
            @test runner_task(stalled_runner) !== nothing
            Threads.atomic_add!(stalls, 1)
            put!(owned_agent.release, nothing)
        end)

        @test stalls[] >= 1
        @test owned_agent.closed
        @test is_closed(runner)
        @test_throws ArgumentError close(runner, -0.1)
    end

    @testset "Close Before Assigned Task Claims Lifecycle" begin
        mutable struct UnclaimedRunnerAgent
            starts::Int
            work::Int
            closes::Int
        end

        Agent.name(::UnclaimedRunnerAgent) = "unclaimed-runner"
        Agent.on_start(agent::UnclaimedRunnerAgent) = (agent.starts += 1)
        Agent.do_work(agent::UnclaimedRunnerAgent) = (agent.work += 1; 0)
        Agent.on_close(agent::UnclaimedRunnerAgent) = (agent.closes += 1)

        owned_agent = UnclaimedRunnerAgent(0, 0, 0)
        runner = AgentRunner(YieldingIdleStrategy(), owned_agent)
        start_on_thread(runner, Threads.threadid())
        close(runner)

        @test owned_agent.starts == 0
        @test owned_agent.work == 0
        @test owned_agent.closes == 1
        @test istaskdone(runner_task(runner))
        @test is_closed(runner)
    end

    @testset "Concurrent Close Has One Cleanup Owner" begin
        mutable struct ConcurrentCloseRunnerAgent
            started::Channel{Nothing}
            closes::Int
        end

        Agent.name(::ConcurrentCloseRunnerAgent) = "concurrent-close-runner"
        Agent.on_start(agent::ConcurrentCloseRunnerAgent) = put!(agent.started, nothing)
        Agent.do_work(::ConcurrentCloseRunnerAgent) = (sleep(0.001); 0)
        Agent.on_close(agent::ConcurrentCloseRunnerAgent) = (agent.closes += 1)

        owned_agent = ConcurrentCloseRunnerAgent(Channel{Nothing}(1), 0)
        runner = AgentRunner(YieldingIdleStrategy(), owned_agent)
        start(runner)
        take!(owned_agent.started)

        closers = ntuple(_ -> Threads.@spawn(close(runner)), 3)
        foreach(fetch, closers)

        @test owned_agent.closes == 1
        @test is_closed(runner)
        @test istaskdone(runner_task(runner))
    end

    @testset "Concurrent Start and Close" begin
        mutable struct StartCloseRaceRunnerAgent
            starts::Int
            closes::Int
        end

        Agent.name(::StartCloseRaceRunnerAgent) = "start-close-race"
        Agent.on_start(agent::StartCloseRaceRunnerAgent) = (agent.starts += 1)
        Agent.on_close(agent::StartCloseRaceRunnerAgent) = (agent.closes += 1)
        Agent.do_work(::StartCloseRaceRunnerAgent) = 0

        for _ in 1:64
            owned_agent = StartCloseRaceRunnerAgent(0, 0)
            runner = AgentRunner(NoOpIdleStrategy(), owned_agent)
            gate = Channel{Nothing}(2)

            starter = Threads.@spawn begin
                take!(gate)
                try
                    start(runner)
                    :started
                catch exception
                    exception isa ArgumentError || rethrow()
                    :closed_first
                end
            end
            closer = Threads.@spawn begin
                take!(gate)
                close(runner)
            end
            put!(gate, nothing)
            put!(gate, nothing)

            fetch(starter)
            fetch(closer)
            @test is_closed(runner)
            @test owned_agent.starts in 0:1
            @test owned_agent.closes == 1
        end
    end
end
