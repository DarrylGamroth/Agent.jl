"""
Status values for a `DynamicCompositeAgent`.
"""
@enum DynamicCompositeStatus INIT ACTIVE CLOSED

"""
Dynamic composite agent that allows agents to be added and removed.
"""
mutable struct DynamicCompositeAgent

    agent_name::String
    agents::Vector{Any}
    @atomic status::DynamicCompositeStatus
    pending_add::Base.RefValue{Any}
    pending_remove::Base.RefValue{Any}
    lock::Threads.SpinLock

    function DynamicCompositeAgent(
        agent_name::String,
        agents::Vector{Any},
        status::DynamicCompositeStatus,
        pending_add::Base.RefValue{Any},
        pending_remove::Base.RefValue{Any},
        lock::Threads.SpinLock,
    )
        new(agent_name, agents, status, pending_add, pending_remove, lock)
    end
end

function DynamicCompositeAgent(agent_name::String)
    return DynamicCompositeAgent(
        agent_name,
        Any[],
        INIT,
        Ref{Any}(nothing),
        Ref{Any}(nothing),
        Threads.SpinLock(),
    )
end

function DynamicCompositeAgent(agent_name::String, agents::AbstractVector)
    for agent in agents
        agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    end

    agents_vector = Vector{Any}(agents)
    return DynamicCompositeAgent(
        agent_name,
        agents_vector,
        INIT,
        Ref{Any}(nothing),
        Ref{Any}(nothing),
        Threads.SpinLock(),
    )
end

function DynamicCompositeAgent(agent_name::String, agents::Vararg{Any})
    if length(agents) == 1 && agents[1] isa AbstractVector
        return DynamicCompositeAgent(agent_name, agents[1])
    end

    return DynamicCompositeAgent(agent_name, collect(agents))
end

name(agent::DynamicCompositeAgent) = agent.agent_name

"""
    status(agent::DynamicCompositeAgent)

Return the current status of the dynamic composite agent.
"""
status(agent::DynamicCompositeAgent) = @atomic :acquire agent.status

function on_start(agent::DynamicCompositeAgent)
    for sub_agent in agent.agents
        on_start(sub_agent)
    end

    @atomic :release agent.status = ACTIVE
    return nothing
end

function do_work(agent::DynamicCompositeAgent)
    agent_to_add = nothing
    agent_to_remove = nothing

    lock(agent.lock)
    try
        if agent.pending_add[] !== nothing
            agent_to_add = agent.pending_add[]
            agent.pending_add[] = nothing
        end
        if agent.pending_remove[] !== nothing
            agent_to_remove = agent.pending_remove[]
            agent.pending_remove[] = nothing
        end
    finally
        unlock(agent.lock)
    end

    if agent_to_add !== nothing
        add_agent!(agent, agent_to_add)
    end

    if agent_to_remove !== nothing
        remove_agent!(agent, agent_to_remove)
    end

    work_count = 0
    for sub_agent in agent.agents
        work_count += do_work(sub_agent)
    end
    return work_count
end

function on_close(agent::DynamicCompositeAgent)
    @atomic :release agent.status = CLOSED

    errors = Exception[]
    for sub_agent in agent.agents
        try
            on_close(sub_agent)
        catch e
            push!(errors, e)
        end
    end

    empty!(agent.agents)

    lock(agent.lock)
    try
        agent.pending_add[] = nothing
        agent.pending_remove[] = nothing
    finally
        unlock(agent.lock)
    end

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

"""
    try_add(agent::DynamicCompositeAgent, sub_agent)

Request adding an agent; returns `true` if queued.
"""
function try_add(agent::DynamicCompositeAgent, sub_agent)
    sub_agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    if status(agent) != ACTIVE
        throw(ArgumentError("add called when not active"))
    end

    lock(agent.lock)
    try
        if agent.pending_add[] !== nothing
            return false
        end
        agent.pending_add[] = sub_agent
        return true
    finally
        unlock(agent.lock)
    end
end

"""
    has_add_completed(agent::DynamicCompositeAgent)

Return `true` if the last add request has been processed.
"""
function has_add_completed(agent::DynamicCompositeAgent)
    if status(agent) != ACTIVE
        throw(ArgumentError("agent is not active"))
    end

    lock(agent.lock)
    try
        return agent.pending_add[] === nothing
    finally
        unlock(agent.lock)
    end
end

"""
    try_remove(agent::DynamicCompositeAgent, sub_agent)

Request removing an agent; returns `true` if queued.
"""
function try_remove(agent::DynamicCompositeAgent, sub_agent)
    sub_agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    if status(agent) != ACTIVE
        throw(ArgumentError("remove called when not active"))
    end

    lock(agent.lock)
    try
        if agent.pending_remove[] !== nothing
            return false
        end
        agent.pending_remove[] = sub_agent
        return true
    finally
        unlock(agent.lock)
    end
end

"""
    has_remove_completed(agent::DynamicCompositeAgent)

Return `true` if the last remove request has been processed.
"""
function has_remove_completed(agent::DynamicCompositeAgent)
    if status(agent) != ACTIVE
        throw(ArgumentError("agent is not active"))
    end

    lock(agent.lock)
    try
        return agent.pending_remove[] === nothing
    finally
        unlock(agent.lock)
    end
end

function add_agent!(agent::DynamicCompositeAgent, sub_agent)
    try
        on_start(sub_agent)
    catch e
        try
            on_close(sub_agent)
        catch close_e
            throw(CompositeException([e, close_e]))
        end
        throw(e)
    end

    push!(agent.agents, sub_agent)
    return nothing
end

function remove_agent!(agent::DynamicCompositeAgent, sub_agent)
    idx = findfirst(existing -> existing === sub_agent, agent.agents)
    idx === nothing && return nothing

    try
        on_close(sub_agent)
    finally
        deleteat!(agent.agents, idx)
    end
    return nothing
end

export DynamicCompositeAgent,
    DynamicCompositeStatus,
    status,
    try_add,
    has_add_completed,
    try_remove,
    has_remove_completed
