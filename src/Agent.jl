module Agent

using StableTasks

include("idlestrategy.jl")
include("backoffidlestrategy.jl")
include("busyspinidlestrategy.jl")
include("noopidlestrategy.jl")
include("sleepingidlestrategy.jl")
include("sleepingmillisidlestrategy.jl")
include("yieldingidlestrategy.jl")
include("controllableidlestrategy.jl")
include("abstractagent.jl")
include("errorhandling.jl")
include("compositeagent.jl")
include("dynamiccompositeagent.jl")
include("agentinvoker.jl")
include("agentrunner.jl")

end # module Agent
