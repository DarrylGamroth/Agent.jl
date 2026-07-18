using Pkg

function git_value(command::Cmd)
    try
        return strip(read(command, String))
    catch
        return "unavailable"
    end
end

function print_benchmark_environment()
    repository_root = normpath(joinpath(@__DIR__, ".."))
    revision = git_value(`git -C $repository_root rev-parse HEAD`)
    status = git_value(`git -C $repository_root status --short`)
    kernel_release = git_value(`uname -r`)

    println("Source revision: ", revision)
    println("Source tree: ", isempty(status) ? "clean" : "dirty")
    println("Julia: ", VERSION)
    println("Active project: ", Base.active_project())
    println("CPU: ", Sys.CPU_NAME)
    println("OS/architecture: ", Sys.KERNEL, "/", Sys.ARCH)
    println("Kernel: ", kernel_release)
    println(
        "Julia threads: default=",
        Threads.nthreads(:default),
        ", interactive=",
        Threads.nthreads(:interactive),
    )
    println("Julia command: ", Base.julia_cmd())
    Pkg.status(; mode=Pkg.PKGMODE_PROJECT)
    return nothing
end
