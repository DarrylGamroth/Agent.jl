"""
Group multiple agents into a composite so they can be scheduled as a unit.
"""
mutable struct CompositeAgent{T<:Tuple}
    agents::T
    composite_name::String
    agent_index::Int
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
    return CompositeAgent(agents, composite_name, 1)
end

CompositeAgent(agents::Vararg{Any}) = CompositeAgent(agents)

name(agent::CompositeAgent) = agent.composite_name

function on_start(agent::CompositeAgent)
    agent.agent_index = 1
    errors = Exception[]
    _on_start_tuple!(agent.agents, errors)

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

function do_work(agent::CompositeAgent)
    return _do_work_tuple!(agent)
end

@generated function _do_work_tuple!(agent::CompositeAgent{T}) where {T<:Tuple}
    duty_cycles = [
        quote
            if agent.agent_index <= $index
                agent.agent_index = $(index + 1)
                work_count += do_work(getfield(agent.agents, $index))
            end
        end for index in 1:fieldcount(T)
    ]

    return quote
        work_count = 0
        $(duty_cycles...)
        agent.agent_index = 1
        return work_count
    end
end

@inline _on_start_tuple!(::Tuple{}, errors::Vector{Exception}) = nothing
@inline function _on_start_tuple!(agents::Tuple, errors::Vector{Exception})
    try
        on_start(first(agents))
    catch e
        push!(errors, e)
    end
    return _on_start_tuple!(Base.tail(agents), errors)
end

function on_close(agent::CompositeAgent)
    agent.agent_index = 1
    errors = Exception[]
    _on_close_tuple!(agent.agents, errors)

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

@inline _on_close_tuple!(::Tuple{}, errors::Vector{Exception}) = nothing
@inline function _on_close_tuple!(agents::Tuple, errors::Vector{Exception})
    try
        on_close(first(agents))
    catch e
        push!(errors, e)
    end
    return _on_close_tuple!(Base.tail(agents), errors)
end

export CompositeAgent
