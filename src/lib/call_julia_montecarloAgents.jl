# using StaticArrays
# using LinearAlgebra
# using ForwardDiff
# using Distributions
# using ProgressMeter

using CellListMap.PeriodicSystems
import CellListMap.wrap_relative_to
import CellListMap.limits, CellListMap.Box
using Random

Random.seed!(1)

function computeAgents(Nm,Na,tau,SARDp)

    Nm = Int(Nm)
    Na = Int(Na)
    tau = Float64(tau)

    Agents0 = zeros(Nm,Na,2)
    AgentsT = zeros(Nm,Na,2)
    cutoff = max(SARDp.hA, SARDp.hR)

    for m in 1:Nm
        println("("*string(m)*"/"*string(Nm)*")")
        system = init_system(Na = Na, cutoff = cutoff)
        Agents0[m,:,:] .= vecvec2mat(system.positions)
        AgentsT[m,:,:] = sampleAgents(system,Na,tau,SARDp)
    end 

    return Agents0,AgentsT
end

function init_system(;Na::Int=200,cutoff::Float64=0.1)
    positions = generatePositions(Na)    
    unitcell = [1.0, 1.0]
    system = PeriodicSystem(
        positions=positions,
        cutoff=cutoff,
        unitcell = [1.0, 1.0],
        output=similar(positions),
        output_name=:interaction,
        parallel=true,
    )
    return system
end

function generatePositions(Na)
    σ = 0.2
    X = MvNormal([0.5,0.5],σ*I(2))

    positions = [SVector{2,Float64}(rand(X)) for _ in 1:Na]
    while any(particleOut.(positions))
        positions[particleOut.(positions)] = 
            [SVector{2,Float64}(rand(X)) for _ in 1:sum(particleOut.(positions))]
    end

    return positions
end

function sampleAgents(system,Na,tau,SARDp; dt=1e-2)

    nsteps = round(Int,tau/dt)
    X = MvNormal([0.0,0.0],I(2))

    @showprogress for step in 1:nsteps

        # compute pairwise interacitons interaction at this step
        # key point where interactions are computed
        map_pairwise!(
            (x,y,i,j,d2,interaction) -> update_interaction!(x,y,i,j,d2,interaction,Na,SARDp),
            system)

        x = system.positions
        f = system.interaction 
        s = -SARDp.gammaS * ∇Sfun.(system.positions)
        noise = sqrt(2*SARDp.gammaD) * [SVector{2,Float64}(rand(X)) for _ in 1:Na]
        x = x + dt*f + dt*s + sqrt(dt)*noise
        x = fixPositions(x)
        system.positions .= x


    end
    return vecvec2mat(system.positions)

end

function fixPositions(positions)
    for i in eachindex(positions)
        pos = positions[i]
        positions[i] = SVector{2,Float64}([max(min(pos[1],0.999),0.001),max(min(pos[2],0.999),0.001)])
    end
    return positions
end

function update_interaction!(x,y,i,j,d2,interaction,Na,SARDp)
    
    dxy = x-y
    # drift = 1/Na * (SARDp.gammaA * ∇h(dxy,d2,SARDp.hA) + SARDp.gammaR * ∇h(dxy,d2,SARDp.hR))
    
    den = (sqrt(d2) * (-1 + sqrt(d2))^3)
    if den == 0 
        drift = zeros(SVector{2})
    else
        drift = -2 * dxy * (SARDp.gammaA * (d2 ≤ SARDp.hA^2) + 
                + SARDp.gammaR * (d2 ≤ SARDp.hR^2)) / (Na * den)
    end
    interaction[i] += drift
    interaction[j] -= drift

    return interaction
end

# function Sfun(x,y)
#     # return the level of s for every coordinate x,y ∈ [0,1] × [0,1]
#     return (x-0.5)^2+(y-0.5)^2
# end

function Sfun(x,y)
    # return the level of s for every coordinate x,y ∈ [0,1] × [0,1]
    b = 0.2

    # center
    if (b <= x <= 1-b) && (b <= y <= 1-b)
        return 0.0
    # sides
    elseif (x < b) && (b < y < 1-b)
        return (x-b)^2
    elseif (x > 1-b) && (b < y < 1-b)
        return (x-(1-b))^2
    elseif (y < b) && (b < x < 1-b)
        return (y-b)^2
    elseif (y > 1-b) && (b < x < 1-b)
        return (y-(1-b))^2
    # corners
    elseif (x < b) && (y < b)
        return (x-b)^2+(y-b)^2 # ok
    elseif (x < b) && (y > 1 - b)
        return (x-b)^2+(y-(1-b))^2
    elseif (x > 1-b) && (y < b)
        return (x-(1-b))^2+(y-b)^2
    elseif (x > 1-b) && (y > 1-b)
        return (x-(1-b))^2+(y-(1-b))^2 # ok
    else # (x > 1 || x < 0 || y > 1 || y < 0)
        return b^2
    end
end


function Sfun(p)
    return (Sfun(p[1],p[2]))
end

function ∇Sfun(p)
    return ForwardDiff.gradient(Sfun,p)
end

function ∇Sfun(x,y)
    return ForwardDiff.gradient(Sfun,[x,y])
end

function computeS(Npt,Sfun)
    # return X,Y,S of size (Ne_x x Ne_y) 
    # with x coordinates, y coordinates and s level

    Npt = Int(Npt)
    x = LinRange(0,1,Npt)
    y = LinRange(0,1,Npt)
    X = repeat(y',Npt,1)
    Y = repeat(x,1,Npt)

    S = reshape([Float64(Sfun(xi,yi)) for xi in x for yi in y],Npt,Npt)
    return X,Y,S
end

function vecvec2mat(x)
    return reduce(vcat,transpose.(x))
end

function mat2vecvec(x)
    return 
end

function particlesOut(positions)
    if maximum(vecvec2mat(positions)) > 1.0 || minimum(vecvec2mat(positions)) < 0.0
        return true
    else 
        return false
    end
end

function particleOut(position)
    if maximum(position) > 1.0 || minimum(position) < 0.0
        return true
    else 
        return false
    end
end



