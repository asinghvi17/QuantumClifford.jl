"""
$TYPEDSIGNATURES

Fix the clipped gauge of a stabilizer (in place).

Assumes the input is a valid full-rank stabilizer (all operators
commute and have real phases).

```jldoctest
julia> s = S"- X_ZX_X
             + XXYZ__
             - YZ_Z_X
             - XZX__Y
             + _Z_Y_Y
             - ____Z_";

julia> canonicalize_clip!(s)
- X_XY__
+ YZY___
+ _XZX__
- _ZYX_Z
- __YZ_X
- ____Z_
```

If `phases=false` is set, the canonicalization does not track the phases
in the tableau, leading to a significant speedup.

Introduced in [nahum2017quantum](@cite), with a more detailed explanation of the algorithm in Appendix A of [li2019measurement](@cite)

See also: [`canonicalize!`](@ref), [`canonicalize_rref!`](@ref), [`canonicalize_gott!`](@ref).
"""
function canonicalize_clip!(state::AbstractStabilizer; phases::Bool=true)
    _canonicalize_clip!(state; phases=Val(phases))
end
function  _canonicalize_clip!(state::AbstractStabilizer; phases::Val{B}=Val(true)) where B
    # TODO: the function has spurious allocation, to be further optimized
    tab = stabilizerview(state)
    rows, columns = size(stabilizerview(state))
    # step 1: pregauge
    i = 1 # index to place used stab
    for j in 1:columns
        # find first row that is not I in col j
        k1 = findfirst(k->|(tab[k,j]...), i:rows)
        # find second row that is not I and not same as k1
        if k1!==nothing
            k1 += i-1
            k2 = findfirst(k->
                (|(tab[k,j]...) & # not identity
                ((tab[k,j][1]⊻tab[k1,j][1]) | (tab[k,j][2]⊻tab[k1,j][2]))), # not same as k1
                k1+1:columns)
            if k2!==nothing
                k2 += k1
                # move k1 and k2 up to i and i+1
                rowswap!(state, k1, i; phases=phases)
                rowswap!(state, k2, i+1; phases=phases)
                # use them to eliminate others
                for m in i+2:rows
                    if !(tab[m,j][1]⊻tab[i,j][1]) && !(tab[m,j][2]⊻tab[i,j][2])
                        mul_left!(state, m, i; phases=phases)
                    elseif !(tab[m,j][1]⊻tab[i+1,j][1]) && !(tab[m,j][2]⊻tab[i+1,j][2])
                        mul_left!(state, m, i+1; phases=phases)
                    elseif !(tab[m,j][1]⊻tab[i,j][1]⊻tab[i+1,j][1]) && !(tab[m,j][2]⊻tab[i,j][2]⊻tab[i+1,j][2])
                        mul_left!(state, m, i; phases=phases)
                        mul_left!(state, m, i+1; phases=phases)
                    end
                end
                i += 2
            else # can only find k1
                # move k1 up to i
                rowswap!(state, k1, i; phases=phases)
                # use it to eliminate others
                for m in i+1:rows
                    if !(tab[m,j][1]⊻tab[i,j][1]) && !(tab[m,j][2]⊻tab[i,j][2])
                        mul_left!(state, m, i; phases=phases)
                    end
                end
                i += 1
            end
        end
    end
    # step 2: gauge
    unfrozen_rows = Array(rows:-1:1)
    for j in columns:-1:1 # in reversed order to keep left ends
        # find first row that is not I in col j
        k1 = findfirst(k->|(tab[k,j]...), unfrozen_rows)
        # find second row that is not I and not same as k1
        if k1!==nothing
            k1_row = unfrozen_rows[k1]
            k2 = findfirst(k->
                (|(tab[k,j]...) & # not identity
                ((tab[k,j][1]⊻tab[k1_row,j][1]) | (tab[k,j][2]⊻tab[k1_row,j][2]))), # not same as k1
                unfrozen_rows[k1+1:end])

            if k2!==nothing
                k2 += k1
                k2_row = unfrozen_rows[k2]
                # use them to eliminate others
                # for rows between k1 and k2, use k1
                for m in unfrozen_rows[k1+1:k2-1]
                    if !(tab[m,j][1]⊻tab[k1_row,j][1]) && !(tab[m,j][2]⊻tab[k1_row,j][2])
                        mul_left!(state, m, k1_row; phases=phases)
                    end
                end
                # for other rows, use both
                for m in unfrozen_rows[k2+1:end]
                    if !(tab[m,j][1]⊻tab[k1_row,j][1]) && !(tab[m,j][2]⊻tab[k1_row,j][2])
                        mul_left!(state, m, k1_row; phases=phases)
                    elseif !(tab[m,j][1]⊻tab[k2_row,j][1]) && !(tab[m,j][2]⊻tab[k2_row,j][2])
                        mul_left!(state, m, k2_row; phases=phases)
                    elseif !(tab[m,j][1]⊻tab[k1_row,j][1]⊻tab[k2_row,j][1]) && !(tab[m,j][2]⊻tab[k1_row,j][2]⊻tab[k2_row,j][2])
                        mul_left!(state, m, k1_row; phases=phases)
                        mul_left!(state, m, k2_row; phases=phases)
                    end
                end
                deleteat!(unfrozen_rows, (k1, k2))
            else # can only find k1
                # use it to eliminate others
                for m in unfrozen_rows[k1+1:end]
                    if !(tab[m,j][1]⊻tab[k1_row,j][1]) && !(tab[m,j][2]⊻tab[k1_row,j][2])
                        mul_left!(state, m, k1_row; phases=phases)
                    end
                end
                deleteat!(unfrozen_rows, k1)
            end
        end
    end
    state
end


"""
$TYPEDSIGNATURES

Get the bigram of a tableau.

It is the list of endpoints of a tableau in the clipped gauge.

If `clip=true` (the default) the tableau is converted to the clipped gauge in-place before calculating the bigram.
Otherwise, the clip gauge conversion is skipped (for cases where the input is already known to be in the correct gauge).

Introduced in [nahum2017quantum](@cite), with a more detailed explanation of the algorithm in Appendix A of [li2019measurement](@cite)

See also: [`canonicalize_clip!`](@ref)
"""
function bigram(state::AbstractStabilizer; clip::Bool=true)
    clip && canonicalize_clip!(state)
    tab = stabilizerview(state)
    rows, columns = size(tab)
    bg = zeros(Int, rows, 2)
    for i in 1:rows
        bg[i, 1] = findfirst(j->|(tab[i,j]...), 1:columns)
        bg[i, 2] = findlast(j->|(tab[i,j]...), 1:columns)
    end
    bg
end


"""
$TYPEDSIGNATURES

Get bipartite entanglement entropy of a subsystem

Defined as entropy of the reduced density matrix.

It can be calculated with multiple different algorithms,
the most performant one depending on the particular case.

Currently implemented are the `:clip`, `:graph`, and `:rref` algorithms.
Benchmark your particular case to choose the best one.
"""
function entanglement_entropy end


"""
Get bipartite entanglement entropy of a contiguous subsystem by passing through the clipped gauge.

If `clip=false` is set the canonicalization step is skipped, useful if the input state is already in the clipped gauge.

See also: [`bigram`](@ref), [`canonicalize_clip!`](@ref)
"""
function entanglement_entropy(state::AbstractStabilizer, subsystem_range::UnitRange, algorithm::Val{:clip}; clip::Bool=true)
    bg = bigram(state; clip=clip)
    count(r->(r[1] in subsystem_range)⊻(r[2] in subsystem_range), eachrow(bg)) ÷ 2
end


"""
Get bipartite entanglement entropy by first converting the state to a graph and computing the rank of the adjacency matrix.

Based on [hein2006entanglement](@cite).
"""
function entanglement_entropy(state::AbstractStabilizer, subsystem::AbstractVector, algorithm::Val{:graph})
    graph = Graphs.Graph(state)
    adjmat = Graphs.adjacency_matrix(graph)
    other_subsystem = filter(i->!(i in collect(subsystem)), 1:Graphs.nv(graph))
    subadjmat = Nemo.matrix(Nemo.ResidueRing(Nemo.ZZ, 2), collect(adjmat[subsystem,other_subsystem]))
    LinearAlgebra.rank(subadjmat)
end


"""
Get bipartite entanglement entropy by converting to RREF form (i.e., partial trace form).

The state will be partially canonicalized in an RREF form.

See also: [`canonicalize_rref!`](@ref), [`traceout!`](@ref).
"""
function entanglement_entropy(state::AbstractStabilizer, subsystem::AbstractVector, algorithm::Val{:rref})
    nb_of_qubits = nqubits(state)
    nb_of_deletions = length(subsystem)
    state, rank_after_deletion = canonicalize_rref!(state, subsystem)
    return nb_of_qubits - rank_after_deletion - nb_of_deletions
end
