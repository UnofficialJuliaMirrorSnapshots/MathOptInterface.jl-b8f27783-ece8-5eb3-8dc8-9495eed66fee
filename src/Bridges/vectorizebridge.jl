const LPCone{T} = Union{MOI.EqualTo{T}, MOI.LessThan{T}, MOI.GreaterThan{T}}

vector_set(::MOI.EqualTo) = MOI.Zeros(1)
vector_set(::MOI.LessThan) = MOI.Nonpositives(1)
vector_set(::MOI.GreaterThan) = MOI.Nonnegatives(1)

vector_set_type(::Type{<:MOI.EqualTo}) = MOI.Zeros
vector_set_type(::Type{<:MOI.LessThan}) = MOI.Nonpositives
vector_set_type(::Type{<:MOI.GreaterThan}) = MOI.Nonnegatives

"""
    VectorizeBridge{T}

Transforms a constraint `AbstractScalarFunction`-in-`S` where `S <: LPCone` to
`AbstactVectorFunction`-in-`vector_set_type(S)`.
"""
mutable struct VectorizeBridge{T, F, S} <: AbstractBridge
    vector_constraint::CI{F, S}
    set_constant::T # constant in scalar set
end
function VectorizeBridge{T, F, S}(model::MOI.ModelLike,
                                  f::MOI.AbstractScalarFunction,
                                  set::MOI.AbstractScalarSet) where {T, F, S}
    set_constant = MOIU.getconstant(set)
    g = MOIU.operate(-, T, f, set_constant)
    if -set_constant != MOI._constant(g)[1]
        # This means the constant in `f` was not zero
        constant = MOI._constant(g)[1] + set_constant
        throw(MOI.ScalarFunctionConstantNotZero{typeof(constant), typeof(f),
                                                typeof(set)}(constant))
    end
    h = MOIU.operate(vcat, T, g)
    vector_constraint = MOI.add_constraint(model, h, vector_set(set))
    return VectorizeBridge{T, F, S}(vector_constraint, set_constant)
end

function MOI.supports_constraint(::Type{VectorizeBridge{T}},
                                ::Type{<:MOI.AbstractScalarFunction},
                                ::Type{<:LPCone{T}}) where T
    return true
end
function added_constraint_types(::Type{VectorizeBridge{T, F, S}}) where {T, F, S}
    return [(F, S)]
end
function concrete_bridge_type(::Type{<:VectorizeBridge{T}},
                              F::Type{<:MOI.AbstractScalarFunction},
                              S::Type{<:LPCone{T}}) where T
    G = MOIU.promote_operation(-, T, F, T)
    H = MOIU.promote_operation(vcat, T, G)
    return VectorizeBridge{T, H, vector_set_type(S)}
end

# Attributes, Bridge acting as an model
function MOI.get(::VectorizeBridge{T, F, S},
                 ::MOI.NumberOfConstraints{F, S}) where {T, F, S}
    return 1
end
function MOI.get(bridge::VectorizeBridge{T, F, S},
                 ::MOI.ListOfConstraintIndices{F, S}) where {T, F, S}
    return [bridge.vector_constraint]
end

# References
function MOI.delete(model::MOI.ModelLike, bridge::VectorizeBridge)
    MOI.delete(model, bridge.vector_constraint)
end

# Attributes, Bridge acting as a constraint

function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintPrimal,
                 bridge::VectorizeBridge)
    x = MOI.get(model, attr, bridge.vector_constraint)
    @assert length(x) == 1
    y = x[1]
    status = MOI.get(model, MOI.PrimalStatus(attr.N))
    if status != MOI.INFEASIBILITY_CERTIFICATE &&
       status != MOI.NEARLY_INFEASIBILITY_CERTIFICATE
       # If it is an infeasibility certificate, it is a ray and satisfies the
       # homogenized problem, see https://github.com/JuliaOpt/MathOptInterface.jl/issues/433
       # Otherwise, we need to add the set constant since the ConstraintPrimal
       # is defined as the value of the function and the set_constant was
       # removed from the original function
       y += bridge.set_constant
   end
   return y
end
function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintDual,
                 bridge::VectorizeBridge)
    x = MOI.get(model, attr, bridge.vector_constraint)
    @assert length(x) == 1
    return x[1]
end
function MOI.modify(model::MOI.ModelLike, bridge::VectorizeBridge,
                    change::MOI.ScalarCoefficientChange)
    MOI.modify(model, bridge.vector_constraint,
               MOI.MultirowChange(change.variable,
                                  [(1, change.new_coefficient)]))
end
function MOI.set(model::MOI.ModelLike, ::MOI.ConstraintSet,
                 bridge::VectorizeBridge, new_set::LPCone)
    bridge.set_constant = MOIU.getconstant(new_set)
    MOI.modify(model, bridge.vector_constraint,
               MOI.VectorConstantChange([-bridge.set_constant]))
end
