using Test
using Agent
using Aqua

@testset "Aqua quality assurance" begin
    Aqua.test_all(Agent)
end

@testset "Exported API documentation" begin
    if isdefined(Base.Docs, :undocumented_names)
        @test isempty(Base.Docs.undocumented_names(Agent; private=false))
    else
        @test VERSION < v"1.11"
    end
end

# Include all test files
include("test_agent_interface.jl")
include("test_idle_strategies.jl")
include("test_agentrunner.jl")
include("test_runner_liveness.jl")
include("test_agentinvoker.jl")
include("test_compositeagent.jl")
include("test_dynamiccompositeagent.jl")
include("test_integration.jl")
include("test_thread_pinning.jl")
