"""
    DynamicCompositeStatus

Lifecycle states for a `DynamicCompositeAgent`.
"""
@enum DynamicCompositeStatus INIT ACTIVE CLOSED

@doc "The dynamic composite has not started." INIT
@doc "The dynamic composite is active and accepts add/remove requests." ACTIVE
@doc "The dynamic composite has completed shutdown." CLOSED

"""
    DynamicCompositeAgent(name[, agents...])

An Agrona-style composite whose owner executes all agent lifecycle and duty
cycle methods. Other threads may submit at most one pending add and one pending
remove request without blocking. Requests are published through atomic fields;
the runner thread consumes them at the beginning of a duty cycle.
"""
mutable struct DynamicCompositeAgent
    agent_name::String
    agents::Vector{Any}
    @atomic status::DynamicCompositeStatus
    @atomic pending_add::Any
    @atomic pending_remove::Any
    agent_index::Int

    function DynamicCompositeAgent(
        agent_name::String,
        agents::Vector{Any},
        status::DynamicCompositeStatus=INIT,
    )
        new(agent_name, agents, status, nothing, nothing, 1)
    end
end

DynamicCompositeAgent(agent_name::String) = DynamicCompositeAgent(agent_name, Any[])

function DynamicCompositeAgent(agent_name::String, agents::AbstractVector)
    for agent in agents
        agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    end
    return DynamicCompositeAgent(agent_name, Vector{Any}(agents))
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

Return the current lifecycle status.
"""
status(agent::DynamicCompositeAgent) = @atomic :acquire agent.status

function on_start(agent::DynamicCompositeAgent)
    agent.agent_index = 1
    for sub_agent in agent.agents
        on_start(sub_agent)
    end

    @atomic :release agent.status = ACTIVE
    return nothing
end

function do_work(agent::DynamicCompositeAgent)
    agent_to_add = @atomicswap :acquire_release agent.pending_add = nothing
    agent_to_add === nothing || add_agent!(agent, agent_to_add)

    # Consume removal only after add processing succeeds. This preserves an
    # independent pending removal when a newly added agent fails on_start,
    # matching Agrona's request ordering.
    agent_to_remove = @atomicswap :acquire_release agent.pending_remove = nothing
    agent_to_remove === nothing || remove_agent!(agent, agent_to_remove)

    work_count = 0
    agents = agent.agents
    while agent.agent_index <= length(agents)
        sub_agent = agents[agent.agent_index]
        agent.agent_index += 1
        work_count += do_work(sub_agent)
    end
    agent.agent_index = 1
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
    agent.agent_index = 1
    @atomicswap :acquire_release agent.pending_add = nothing
    @atomicswap :acquire_release agent.pending_remove = nothing

    isempty(errors) || throw(CompositeException(errors))
    return nothing
end

"""
    try_add(agent::DynamicCompositeAgent, sub_agent)

Publish a non-blocking add request. Return `false` if another add is already
pending. The composite must be active.
"""
function try_add(agent::DynamicCompositeAgent, sub_agent)
    sub_agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    status(agent) === ACTIVE || throw(ArgumentError("add called when not active"))

    _, success = @atomicreplace :acquire_release :acquire agent.pending_add nothing => sub_agent
    if success && status(agent) !== ACTIVE
        @atomicreplace :release :monotonic agent.pending_add sub_agent => nothing
        throw(ArgumentError("add called when not active"))
    end
    return success
end

"""
    has_add_completed(agent::DynamicCompositeAgent)

Return whether the most recently accepted add request has been consumed.
"""
function has_add_completed(agent::DynamicCompositeAgent)
    status(agent) === ACTIVE || throw(ArgumentError("agent is not active"))
    return (@atomic :acquire agent.pending_add) === nothing
end

"""
    try_remove(agent::DynamicCompositeAgent, sub_agent)

Publish a non-blocking identity-based removal request. Return `false` if
another removal is already pending. The composite must be active.
"""
function try_remove(agent::DynamicCompositeAgent, sub_agent)
    sub_agent === nothing && throw(ArgumentError("agent cannot be nothing"))
    status(agent) === ACTIVE || throw(ArgumentError("remove called when not active"))

    _, success = @atomicreplace :acquire_release :acquire agent.pending_remove nothing => sub_agent
    if success && status(agent) !== ACTIVE
        @atomicreplace :release :monotonic agent.pending_remove sub_agent => nothing
        throw(ArgumentError("remove called when not active"))
    end
    return success
end

"""
    has_remove_completed(agent::DynamicCompositeAgent)

Return whether the most recently accepted removal request has been consumed.
"""
function has_remove_completed(agent::DynamicCompositeAgent)
    status(agent) === ACTIVE || throw(ArgumentError("agent is not active"))
    return (@atomic :acquire agent.pending_remove) === nothing
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
        rethrow()
    end

    push!(agent.agents, sub_agent)
    return nothing
end

function remove_agent!(agent::DynamicCompositeAgent, sub_agent)
    index = findfirst(existing -> existing === sub_agent, agent.agents)
    index === nothing && return nothing

    try
        on_close(sub_agent)
    finally
        deleteat!(agent.agents, index)
    end
    return nothing
end

export DynamicCompositeAgent,
    DynamicCompositeStatus,
    has_add_completed,
    has_remove_completed,
    status,
    try_add,
    try_remove
