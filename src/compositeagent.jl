"""
Group multiple agents into a composite so they can be scheduled as a unit.
"""
struct CompositeAgent{T<:Tuple}
    agents::T
    composite_name::String
end

function CompositeAgent(agents::Tuple)
    if isempty(agents)
        throw(ArgumentError("requires at least one sub-agent"))
    end

    names = String[]
    for agent in agents
        agent === nothing && throw(ArgumentError("agent cannot be nothing"))
        push!(names, name(agent))
    end

    composite_name = "[" * join(names, ",") * "]"
    return CompositeAgent(agents, composite_name)
end

CompositeAgent(agents::Vararg{Any}) = CompositeAgent(agents)

name(agent::CompositeAgent) = agent.composite_name

function on_start(agent::CompositeAgent)
    errors = Exception[]
    for sub_agent in agent.agents
        try
            on_start(sub_agent)
        catch e
            push!(errors, e)
        end
    end

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

function do_work(agent::CompositeAgent)
    work_count = 0
    for sub_agent in agent.agents
        work_count += do_work(sub_agent)
    end
    return work_count
end

function on_close(agent::CompositeAgent)
    errors = Exception[]
    for sub_agent in agent.agents
        try
            on_close(sub_agent)
        catch e
            push!(errors, e)
        end
    end

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

export CompositeAgent
