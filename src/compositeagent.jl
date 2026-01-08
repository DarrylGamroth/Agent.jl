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
    _on_start_tuple!(agent.agents, errors)

    if !isempty(errors)
        throw(CompositeException(errors))
    end
    return nothing
end

function do_work(agent::CompositeAgent)
    return _do_work_tuple(agent.agents)
end

@inline _do_work_tuple(::Tuple{}) = 0
@inline function _do_work_tuple(agents::Tuple)
    return do_work(first(agents)) + _do_work_tuple(Base.tail(agents))
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
