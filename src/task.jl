"""
    @taskat tid -> task
Mimics `Threads.@spawn`, but assigns the task to thread `tid` (with `sticky = true`) and
returns the task object instead of scheduling it.

Note for Julia >= 1.9: Threads in the `:interactive` thread pool come after those in
`:default`. Hence, use a thread id `tid > nthreads(:default)` to spawn computations on
"interactive" threads.

# Example
```julia
julia> t = @tspawnat 4 Threads.threadid()
Task (runnable) @0x0000000010743c70
julia> fetch(t)
4
```
"""
macro taskat(thrdid, ex)
    # Copied from ThreadPinning.jl
    # Copied from ThreadPools.jl with the change task.sticky = false -> true
    # https://github.com/tro3/ThreadPools.jl/blob/c2c99a260277c918e2a9289819106dd38625f418/src/macros.jl#L244
    letargs = Base._lift_one_interp!(ex)

    thunk = Base.replace_linenums!(:(() -> ($(esc(ex)))), __source__)
    var = esc(Base.sync_varname)
    tid = esc(thrdid)
    @static if VERSION < v"1.9-"
        nt = :(Threads.nthreads())
    else
        nt = :(Threads.maxthreadid())
    end
    quote
        if $tid < 1 || $tid > $nt
            throw(ArgumentError("Invalid thread id ($($tid)). Must be between in " *
                                "1:(total number of threads), i.e. $(1:$nt)."))
        end
        let $(letargs...)
            local task = Task($thunk)
            task.sticky = true
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, $tid - 1)
            if $(Expr(:islocal, var))
                put!($var, task)
            end
            task
        end
    end
end


"""
    @taskthreadpool [:default|:interactive] expr

Copied from Threads.@spawn to create a [`Task`](@ref) to run on any available thread in
the specified threadpool (`:default` if unspecified).
"""
macro taskthreadpool(args...)
    tp = QuoteNode(:default)
    na = length(args)
    if na == 2
        ttype, ex = args
        if ttype isa QuoteNode
            ttype = ttype.value
            if ttype !== :interactive && ttype !== :default
                throw(ArgumentError("unsupported threadpool in @task: $ttype"))
            end
            tp = QuoteNode(ttype)
        else
            tp = ttype
        end
    elseif na == 1
        ex = args[1]
    else
        throw(ArgumentError("wrong number of arguments in @task"))
    end

    letargs = Base._lift_one_interp!(ex)

    thunk = Base.replace_linenums!(:(() -> ($(esc(ex)))), __source__)
    var = esc(Base.sync_varname)
    quote
        let $(letargs...)
            local task = Task($thunk)
            task.sticky = false
            Threads._spawn_set_thrpool(task, $(esc(tp)))
            if $(Expr(:islocal, var))
                put!($var, task)
            end
            task
        end
    end
end

