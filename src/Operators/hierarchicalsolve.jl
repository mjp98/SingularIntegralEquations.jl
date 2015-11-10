#
# hierarchicalsolve
#

# Continuous analogues for low-rank operators case

\{U<:Operator,V<:AbstractLowRankOperator}(H::HierarchicalOperator{U,V},f::Fun) = hierarchicalsolve(H,f)
\{U<:Operator,V<:AbstractLowRankOperator,F<:Fun}(H::HierarchicalOperator{U,V},f::Vector{F}) = hierarchicalsolve(H,f)

hierarchicalsolve{U<:Operator,V<:AbstractLowRankOperator}(H::HierarchicalOperator{U,V},f::Fun) = hierarchicalsolve(H,[f])[1]

hierarchicalsolve(H::Operator,f::Fun) = H\f
hierarchicalsolve{F<:Fun}(H::Operator,f::Vector{F}) = vec(H\transpose(f))

function hierarchicalsolve{U<:Operator,V<:AbstractLowRankOperator,F<:Fun}(H::HierarchicalOperator{U,V},f::Vector{F})
    N,nf = length(space(first(f))),length(f)

    # Pre-compute Factorization

    !isfactored(H) && factorize!(H)

    # Partition HierarchicalOperator

    (H11,H22),(H21,H12) = partition(H)

    # Off-diagonal low-rank matrix assembly

    U12,V12 = H12.U,H12.V
    U21,V21 = H21.U,H21.V

    # Partition the right-hand side

    (f1,f2) = partition(f,N,space(first(U12)))#space(first(U21)))

    # Solve recursively

    H22f2,H11f1 = hierarchicalsolve(H22,f2),hierarchicalsolve(H11,f1)

    # Compute pivots

    v12,v21 = computepivots(V12,V21,H11f1,H22f2,H.factorization,nf)

    # Solve again with updated right-hand sides

    RHS1 = f1 - v12.'*U12
    RHS2 = f2 - v21.'*U21

    sol = [hierarchicalsolve(H11,RHS1);hierarchicalsolve(H22,RHS2)]

    return assemblesolution(sol,N,nf)
end

function factorize!{U<:Operator,V<:AbstractLowRankOperator}(H::HierarchicalOperator{U,V})
    # Partition HierarchicalOperator

    (H11,H22),(H21,H12) = partition(H)

    # Off-diagonal low-rank matrix assembly

    U12,V12 = H12.U,H12.V
    U21,V21 = H21.U,H21.V

    # Solve recursively

    H22U21,H11U12 = hierarchicalsolve(H22,U21),hierarchicalsolve(H11,U12)

    # Compute A

    fillpivotmatrix!(H.A,V12,V21,H22U21,H11U12)

    # Compute factorization

    H.factorization = pivotldufact(H.A,length(V12),length(V21))#lufact(H.A)
    H.factored = true
end

function fillpivotmatrix!{A1,A2,T}(A::Matrix{T},V12::Vector{Functional{T}},V21::Vector{Functional{T}},H22U21::Vector{Fun{A1,T}},H11U12::Vector{Fun{A2,T}})
    r1,r2 = length(V12),length(V21)
    for i=1:r1,j=1:r2
        A[i,j+r1] += V12[i]*H22U21[j]
        A[j+r2,i] += V21[j]*H11U12[i]
    end
end

function fillpivotmatrix!{V1,V2,A1,A2,T}(A::Matrix{T},V12::Vector{Fun{V1,T}},V21::Vector{Fun{V2,T}},H22U21::Vector{Fun{A1,T}},H11U12::Vector{Fun{A2,T}})
    r1,r2 = length(V12),length(V21)
    for i=1:r1,j=1:r2
        A[i,j+r1] += linedotu(V12[i],H22U21[j])
        A[j+r2,i] += linedotu(V21[j],H11U12[i])
    end
end

function computepivots{A1,A2,T}(V12::Vector{Functional{T}},V21::Vector{Functional{T}},H11f1::Vector{Fun{A1,T}},H22f2::Vector{Fun{A2,T}},A::PivotLDU{T},nf::Int)
    r1,r2 = length(V12),length(V21)
    b1,b2 = zeros(T,r1,nf),zeros(T,r2,nf)
    for i=1:nf
        for j=1:r1
            b1[j,i] += V12[j]*H22f2[i]
        end
        for j=1:r2
            b2[j,i] += V21[j]*H11f1[i]
        end
    end
    A_ldiv_B1B2!(A,b1,b2)
end

function computepivots{V1,V2,A1,A2,T}(V12::Vector{Fun{V1,T}},V21::Vector{Fun{V2,T}},H11f1::Vector{Fun{A1,T}},H22f2::Vector{Fun{A2,T}},A::PivotLDU{T},nf::Int)
    r1,r2 = length(V12),length(V21)
    b1,b2 = zeros(T,r1,nf),zeros(T,r2,nf)
    for i=1:nf
        for j=1:r1
            b1[j,i] += linedotu(V12[j],H22f2[i])
        end
        for j=1:r2
            b2[j,i] += linedotu(V21[j],H11f1[i])
        end
    end
    A_ldiv_B1B2!(A,b1,b2)
end




# Utilities
#=
function partition{PWS<:PiecewiseSpace,T}(f::Fun{PWS,T})
    N = length(space(f))
    N2 = div(N,2)
    if N2 == 1
        return (pieces(f)[1]),(pieces(f)[2])
    else
        return (depiece(pieces(f)[1:N2])),(depiece(pieces(f)[1+N2:N]))
    end
end

function partition{PWS<:PiecewiseSpace,T}(f::Vector{Fun{PWS,T}})
    N = length(space(first(f)))
    N2 = div(N,2)
    if N2 == 1
        return (map(x->pieces(x)[1],f),map(x->pieces(x)[2],f))
    else
        return (map(x->depiece(pieces(x)[1:N2]),f),map(x->depiece(pieces(x)[1+N2:N]),f))
    end
end
=#

function partition{PWS<:PiecewiseSpace,S<:PiecewiseSpace,T}(f::Fun{PWS,T},N::Int,sp::S)
    N2 = length(sp)
    if N > N2+1
        pf = pieces(f)
        return (depiece(pf[1:N2])),(depiece(pf[1+N2:N]))
    else
        pf = pieces(f)
        return (depiece(pf[1:N2])),(pf[N])
    end
end

function partition{PWS<:PiecewiseSpace,S,T}(f::Fun{PWS,T},N::Int,sp::S)
    if N == 2
        pf = pieces(f)
        return (pf[1],pf[2])
    else
        pf = pieces(f)
        return (pf[1],pf[2:N])
    end
end

function partition{PWS<:PiecewiseSpace,S,T}(f::Vector{Fun{PWS,T}},N::Int,sp::S)
    p1 = partition(f[1],N,sp)
    ret1,ret2 = fill(p1[1],length(f)),fill(p1[2],length(f))
    for k=2:length(f)
        ret1[k],ret2[k] = partition(f[k],N,sp)
    end
    ret1,ret2
end


function assemblesolution(sol,N::Int,nf::Int)
    if N == 2
        if nf == 1
            return [mapreduce(i->depiece(sol[i:nf:end]),vcat,1:nf)]
        else
            return collect(mapreduce(i->depiece(sol[i:nf:end]),vcat,1:nf))
        end
    else
        ls = length(sol)
        if nf == 1
            return [mapreduce(i->depiece(mapreduce(k->pieces(sol[k]),vcat,i:nf:ls)),vcat,1:nf)]
        else
            return collect(mapreduce(i->depiece(mapreduce(k->pieces(sol[k]),vcat,i:nf:ls)),vcat,1:nf))
        end
    end
end
