# Copyright 2024-2026 Rubus Technologies Inc.
# SPDX-License-Identifier: Apache-2.0

using Pkg

Pkg.activate(@__DIR__)
cd(@__DIR__) do
    # Keep the manifest portable by recording Agent as the relative path `..`.
    Pkg.develop(PackageSpec(path=".."))
end
Pkg.instantiate()
