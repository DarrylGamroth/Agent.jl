# Agent.jl benchmarks

Develop the current checkout into the isolated benchmark environment, then run
the suite from the repository root:

```sh
julia --startup-file=no --project=benchmark benchmark/setup.jl
julia --startup-file=no --threads=4 --project=benchmark benchmark/runbenchmarks.jl
```

`setup.jl` uses `Pkg.develop` with the repository root, so the benchmark always
loads the current checkout rather than a registered Agent release. The
committed manifest locks benchmark-only dependencies and records Agent as the
portable relative path `..`.

The suite contains two deliberately different forms of evidence:

- Closed-loop microbenchmarks of selected invoker, composite, and idle
  primitives, with compilation warmed before sampling.
- Repeated, finite AgentRunner saturation-throughput trials for
  scheduler-managed, thread-assigned, and Linux thread-assigned-plus-pinned
  execution. Each trial verifies the lifecycle, exact duty-cycle count, and
  assigned Julia thread. Pinning trials restore the original affinity.

Runner results are duty cycles per second under closed-loop saturation. They do
not establish fixed-rate latency, tail latency, or production capacity. Compare
repeated runs only on the same controlled host. The report records the source
revision and dirty state, Julia project and version, CPU, OS/kernel, thread
pools, placement, workload size, and repetition count.

The following environment variables control full runner measurements:

- `AGENT_BENCHMARK_CYCLES` (default `1000000`)
- `AGENT_BENCHMARK_REPETITIONS` (default `5`)

CI uses `--smoke` with short workloads in one-thread, multi-thread, and split
default/interactive-pool configurations only to prove that the benchmark
environment and correctness oracles still work. It does not impose timing
thresholds.
