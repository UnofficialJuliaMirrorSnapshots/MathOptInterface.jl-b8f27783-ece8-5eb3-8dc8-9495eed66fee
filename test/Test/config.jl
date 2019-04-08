function atest(model::MOI.ModelLike, config::MOIT.TestConfig)
    @test config.atol == 1e-8
    @test config.rtol == 1e-8
    @test config.solve
    @test config.query
    @test config.duals
    @test config.infeas_certificates
end

function btest(model::MOI.ModelLike, config::MOIT.TestConfig)
    @test false # b is in exclude
end

const customtests = Dict("a" => atest,
                         "b" => btest)

MOIT.@moitestset custom

@testset "TestConfig" begin
    mock = MOIU.MockOptimizer(ModelForMock{Float64}())
    config = MOIT.TestConfig()
    customtest(mock, config, ["b"])
end
