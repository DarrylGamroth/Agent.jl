using Statistics
using ThreadPinning

mutable struct DutyCycleBenchmarkAgent
    target_cycles::Int
    completed_cycles::Int
    started_ns::UInt64
    stopped_ns::UInt64
    observed_thread::Int
    starts::Int
    closes::Int
end

DutyCycleBenchmarkAgent(target_cycles::Int) =
    DutyCycleBenchmarkAgent(target_cycles, 0, 0, 0, 0, 0, 0)

Agent.name(::DutyCycleBenchmarkAgent) = "duty-cycle-benchmark"

function Agent.on_start(agent::DutyCycleBenchmarkAgent)
    agent.starts += 1
    agent.started_ns = time_ns()
    return nothing
end

function Agent.do_work(agent::DutyCycleBenchmarkAgent)
    agent.completed_cycles += 1
    if agent.completed_cycles == 1
        agent.observed_thread = Threads.threadid()
    end
    if agent.completed_cycles == agent.target_cycles
        agent.stopped_ns = time_ns()
        throw(AgentTerminationException())
    end
    return 0
end

function Agent.on_close(agent::DutyCycleBenchmarkAgent)
    agent.closes += 1
    return nothing
end

function assigned_benchmark_thread()
    managed = filter(1:Threads.maxthreadid()) do threadid
        pool = Threads.threadpool(threadid)
        pool === :default || pool === :interactive
    end
    isempty(managed) && error("no managed Julia runtime thread is available")

    dedicated = filter(managed) do threadid
        Threads.nthreads(Threads.threadpool(threadid)) > 1
    end
    return isempty(dedicated) ? last(managed) : last(dedicated)
end

function run_runner_trial(
    mode::Symbol,
    cycles::Int,
    target_thread::Int;
    cpuid::Union{Nothing,Int}=nothing,
)
    owned_agent = DutyCycleBenchmarkAgent(cycles)
    runner = AgentRunner(NoOpIdleStrategy(), owned_agent)

    if mode === :scheduler
        start(runner)
    elseif mode === :assigned
        start_on_thread(runner, target_thread)
    elseif mode === :pinned
        cpuid === nothing && error("pinned trial requires a CPU ID")
        start_on_thread(runner, target_thread; cpuid)
    else
        throw(ArgumentError("unknown runner benchmark mode: $mode"))
    end
    wait(runner)

    owned_agent.completed_cycles == cycles || error("runner completed the wrong cycle count")
    owned_agent.starts == 1 || error("runner called on_start more than once")
    owned_agent.closes == 1 || error("runner called on_close more than once")
    is_closed(runner) || error("runner did not close")
    if mode !== :scheduler && owned_agent.observed_thread != target_thread
        error("assigned runner executed on Julia thread $(owned_agent.observed_thread)")
    end

    elapsed_ns = owned_agent.stopped_ns - owned_agent.started_ns
    elapsed_ns > 0 || error("runner trial recorded a non-positive duration")
    return cycles / (Float64(elapsed_ns) / 1.0e9)
end

function measure_runner_mode(
    mode::Symbol,
    cycles::Int,
    repetitions::Int,
    target_thread::Int;
    cpuid::Union{Nothing,Int}=nothing,
)
    warmup_cycles = min(cycles, max(1_000, cycles ÷ 100))
    run_runner_trial(mode, warmup_cycles, target_thread; cpuid)

    rates = Vector{Float64}(undef, repetitions)
    for repetition in eachindex(rates)
        rates[repetition] = run_runner_trial(mode, cycles, target_thread; cpuid)
    end
    return rates
end

function print_runner_rates(label::AbstractString, rates::Vector{Float64})
    println(
        rpad(label, 30),
        " median=", round(median(rates); digits=1),
        " min=", round(minimum(rates); digits=1),
        " max=", round(maximum(rates); digits=1),
        " cycles/s repetitions=", length(rates),
    )
    return nothing
end

function run_runner_benchmarks(; smoke::Bool=false)
    cycles = parse(
        Int,
        get(ENV, "AGENT_BENCHMARK_CYCLES", smoke ? "10000" : "1000000"),
    )
    repetitions = parse(
        Int,
        get(ENV, "AGENT_BENCHMARK_REPETITIONS", smoke ? "1" : "5"),
    )
    cycles > 0 || throw(ArgumentError("AGENT_BENCHMARK_CYCLES must be positive"))
    repetitions > 0 ||
        throw(ArgumentError("AGENT_BENCHMARK_REPETITIONS must be positive"))

    target_thread = assigned_benchmark_thread()
    pool = Threads.threadpool(target_thread)
    cooperative = Threads.nthreads(pool) == 1

    println("\nAgentRunner closed-loop no-work duty-cycle throughput")
    println("This measures saturation throughput, not fixed-rate latency.")
    println(
        "Workload: cycles=", cycles,
        ", repetitions=", repetitions,
        ", target Julia thread=", target_thread,
        ", pool=", pool,
        ", pool size=", Threads.nthreads(pool),
        ", assigned mode cooperative=", cooperative,
    )

    scheduler_rates = measure_runner_mode(
        :scheduler,
        cycles,
        repetitions,
        target_thread,
    )
    assigned_rates = measure_runner_mode(
        :assigned,
        cycles,
        repetitions,
        target_thread,
    )
    print_runner_rates("scheduler-managed", scheduler_rates)
    print_runner_rates("thread-assigned", assigned_rates)

    if Sys.islinux()
        original_affinity = ThreadPinning.getaffinity(; threadid=target_thread)
        target_cpu = Int(ThreadPinning.getcpuid(; threadid=target_thread))
        try
            pinned_rates = measure_runner_mode(
                :pinned,
                cycles,
                repetitions,
                target_thread;
                cpuid=target_cpu,
            )
            ThreadPinning.getcpuid(; threadid=target_thread) == target_cpu ||
                error("runner target thread was not pinned to the requested CPU")
            print_runner_rates("thread-assigned + pinned", pinned_rates)
            println("Pinned mapping: Julia thread $target_thread -> OS CPU $target_cpu")
        finally
            ThreadPinning.setaffinity(original_affinity; threadid=target_thread)
        end
    else
        println("thread-assigned + pinned      skipped (Linux only)")
    end

    return nothing
end
