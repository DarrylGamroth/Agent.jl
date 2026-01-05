"""
Error counter utilities for agent runners and invokers.
"""

increment_error_counter!(::Nothing) = nothing

function increment_error_counter!(counter::Ref{<:Integer})
    counter[] += 1
    return nothing
end


function handle_error(error_handler, error_counter, agent, error)
    increment_error_counter!(error_counter)
    if error_handler !== nothing
        error_handler(agent, error)
    end
    on_error(agent, error)
    return nothing
end
