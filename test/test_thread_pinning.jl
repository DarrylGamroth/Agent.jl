struct PinningDependencyProbeAgent end

Agent.name(::PinningDependencyProbeAgent) = "pinning-dependency-probe"
Agent.do_work(::PinningDependencyProbeAgent) = throw(AgentTerminationException())

@testset "CPU Pinning Is Opt-In" begin
    @test Base.get_extension(Agent, :AgentThreadPinningExt) === nothing

    runner = AgentRunner(NoOpIdleStrategy(), PinningDependencyProbeAgent())
    exception = try
        start_on_thread(runner, 1; cpuid=0)
        nothing
    catch caught
        caught
    end

    @test exception isa ArgumentError
    @test occursin("load ThreadPinning", sprint(showerror, exception))
    @test !is_started(runner)

    start_on_thread(runner, 1)
    wait(runner)
end

using ThreadPinning

mutable struct AffinityRecordingAgent
    threadid::Int
    cpuid::Int
end

Agent.name(::AffinityRecordingAgent) = "affinity-recording"
function Agent.do_work(agent::AffinityRecordingAgent)
    agent.threadid = Threads.threadid()
    agent.cpuid = ThreadPinning.getcpuid()
    throw(AgentTerminationException())
end

@testset "Optional CPU Pinning" begin
    @test Base.get_extension(Agent, :AgentThreadPinningExt) !== nothing

    runner = AgentRunner(NoOpIdleStrategy(), AffinityRecordingAgent(0, -1))
    if Sys.islinux()
        target_thread = Agent.managed_thread_count()
        original_affinity = ThreadPinning.getaffinity(; threadid=target_thread)
        target_cpu = ThreadPinning.getcpuid(; threadid=target_thread)

        try
            start_on_thread(runner, target_thread; cpuid=target_cpu)
            wait(runner)
            @test agent(runner).threadid == target_thread
            @test agent(runner).cpuid == target_cpu
            @test isone(
                ThreadPinning.getaffinity(; threadid=target_thread)[target_cpu+1],
            )
        finally
            ThreadPinning.setaffinity(original_affinity; threadid=target_thread)
            is_closed(runner) || close(runner)
        end
    else
        @test_throws ArgumentError start_on_thread(runner, 1; cpuid=0)
        @test !is_started(runner)
        close(runner)
    end
end
