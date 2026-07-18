using Agent
using BenchmarkTools

include("environment.jl")
include("runnerbenchmarks.jl")

const SMOKE_TEST = "--smoke" in ARGS

struct BenchmarkAgent end
Agent.name(::BenchmarkAgent) = "benchmark"
Agent.do_work(::BenchmarkAgent) = 0

println("Agent.jl benchmarks")
print_benchmark_environment()
println("Mode: ", SMOKE_TEST ? "CI smoke test" : "measurement")

invoker = AgentInvoker(BenchmarkAgent())
start(invoker)
composite = CompositeAgent(BenchmarkAgent(), BenchmarkAgent())
noop = NoOpIdleStrategy()
backoff = BackoffIdleStrategy()

# Compile and initialise mutable state before collecting samples.
invoke_unchecked(invoker)
Agent.do_work(composite)
Agent.idle(noop, 0)
Agent.idle(backoff, 0)
Agent.reset(backoff)

suite = BenchmarkGroup()
suite["AgentInvoker.invoke_unchecked"] = @benchmarkable invoke_unchecked($invoker) evals=1
suite["CompositeAgent.do_work"] = @benchmarkable Agent.do_work($composite) evals=1
suite["NoOpIdleStrategy.idle"] = @benchmarkable Agent.idle($noop, 0) evals=1
suite["BackoffIdleStrategy idle/reset"] = @benchmarkable begin
    Agent.idle($backoff, 0)
    Agent.reset($backoff)
end evals=1

micro_results = run(
    suite;
    seconds=SMOKE_TEST ? 0.05 : 1.0,
    samples=SMOKE_TEST ? 10 : 10_000,
)
display(micro_results)

close(invoker)
run_runner_benchmarks(; smoke=SMOKE_TEST)
