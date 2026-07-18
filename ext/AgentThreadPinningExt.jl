module AgentThreadPinningExt

using Agent
using ThreadPinning

function pin_assigned_thread!(threadid::Int, cpuid::Int)
    Sys.islinux() || throw(
        ArgumentError("CPU pinning through ThreadPinning.jl is supported only on Linux"),
    )
    ThreadPinning.pinthread(cpuid; threadid)
    return nothing
end

end # module AgentThreadPinningExt
