
"""
    test_ClustData(t::ClustData,ref::ClustData)

Test if the two structs ClustData are identical in key properties
"""
function test_ClustData(t::ClustData,ref::ClustData)
    @test t.region == ref.region
    @test t.K == ref.K
    @test t.T == ref.T
    @test all(t.weights .≈ ref.weights)
    @test all(t.delta_t .≈ ref.delta_t)
    @test all(t.k_ids .≈ ref.k_ids)
    for (k,v) in t.data
        @test all(isapprox.(t.data[k], ref.data[k]), rtol=1e-3)
        @test all(isapprox.(t.mean[k], ref.mean[k]), rtol=1e-3)
        @test all(isapprox.(t.sdv[k], ref.sdv[k]), rtol=1e-3)
    end
end


"""
    test_ClustResult

Tests if the two structs ClustResult are identical in key properties
"""
function test_ClustResult(t::AbstractClustResult,ref::AbstractClustResult)
    @test t.cost ≈ ref.cost
    test_ClustData(t.clust_data,ref.clust_data)
end
