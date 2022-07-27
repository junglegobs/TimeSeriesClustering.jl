
"""
    run_clust(data::ClustData;
      norm_op::String="zscore",
      norm_scope::String="full",
      method::String="kmeans",
      representation::String="centroid",
      n_clust::Int=5,
      n_seg::Int=data.T,
      n_init::Int=1000,
      iterations::Int=300,
      attribute_weights::Dict{String,Float64}=Dict{String,Float64}(),
      save::String="",#QUESTION dead?
      get_all_clust_results::Bool=false,
      kwargs...)

Take input data `data` of dimensionality `N x T` and cluster into data of dimensionality `K x T`.


The following combinations of `method` and `representation` are supported by `run_clust`:

Name | method | representation | comment
:--- | :-------------- | :-------------- | :----
k-means clustering | `<kmeans>` | `<centroid>` | -
k-means clustering with medoid representation | `<kmeans>` | `<medoid>` | -
k-medoids clustering (partitional) | `<kmedoids>` | `<medoid>` | -
k-medoids clustering (exact) | `<kmedoids_exact>` | `<medoid>` | requires Gurobi and the additional keyword argument `kmexact_optimizer`. See [examples] folder for example use. Set `n_init=1`
hierarchical clustering with centroid representation | `<hierarchical>` | `<centroid>` | set `n_init=1`
hierarchical clustering with medoid representation | `<hierarchical>` | `<medoid>` | set `n_init=1`

The other optional inputs are:

Keyword | options | comment
:------ | :------ | :-----
`norm_op` | `zscore` | Normalization operation. `0-1` not yet implemented
`norm_scope` | `full`,`sequence`,`hourly` | Normalization scope. The default (`full`) is used in most of the current literature.
`n_clust` | e.g. `5` | Number of clusters that you want to obtain
`n_seg` | e.g. `10` | Number of segments per period. Not yet implemented, keep as default value.
`n_init` | e.g. `1000` | Number of initializations of locally converging clustering algorithms. `10000` often yields very stable results.
`iterations` | e.g. `300` | Internal parameter of the partitional clustering algorithms.
`attribute_weights` | e.g. Dict("wind-germany"=>3,"solar-germany"=>1,"el_demand-germany"=>5) | weights the respective attributes when clustering. In this example, demand and wind are deemed more important than solar.
`save` | `false` | Save clustered data as csv or jld2 file. Not yet implemented.
`get_all_clust_results` | `true`,`false` | `false` gives a `ClustData` struct with only the best locally converged solution in terms of clustering measure. `true` gives a `ClustDataAll` struct as output, with all locally converged solutions.
`kwargs` | e.g. `kmexact_optimizer` | optional keyword arguments that are required for specific methods, for example k-medoids exact.
"""
function run_clust(data::ClustData;
      norm_op::String="zscore",
      norm_scope::String="full",
      method::String="kmeans",
      representation::String="centroid",
      n_clust::Int=5,
      n_seg::Int=data.T,
      n_init::Int=1000,
      iterations::Int=300,
      attribute_weights::Dict{String,Float64}=Dict{String,Float64}(),
      save::String="",#QUESTION dead?
      get_all_clust_results::Bool=false,
      kwargs...
    )

    # When adding new methods: add combination of clust+rep to sup_kw_args
    check_kw_args(norm_op,norm_scope,method,representation)

    #clustering
    clust_data, cost, centers_all, weights_all, clustids_all, cost_all, iter_all =run_clust_method(data;norm_op=norm_op, norm_scope=norm_scope, method=method, representation=representation, n_clust=n_clust, n_init=n_init, iterations=iterations, attribute_weights=attribute_weights, orig_k_ids=deepcopy(data.k_ids), kwargs...)

     # inter period segmentation (reduce the number of time steps per cluster - not fully implemented yet)
       if n_seg!=data.T &&  n_seg!=0
       clust_data_merged = ClustDataMerged(clust_data)
       segmented_merged=intraperiod_segmentation(clust_data_merged;n_seg=n_seg,norm_scope=norm_scope,iterations=iterations)
       clust_data = ClustData(segmented_merged)
     else # if interperiod segmentation is not used
       n_seg=clust_data.T
     end

    # set configuration file
    clust_config = set_clust_config(;norm_op=norm_op, norm_scope=norm_scope, method=method, representation=representation, n_clust=n_clust, n_seg=n_seg, n_init=n_init, iterations=iterations, attribute_weights=attribute_weights)

    if get_all_clust_results
      # save all locally converged solutions and the best into a struct
      clust_result = ClustResultAll(clust_data,cost,clust_config,centers_all,weights_all,clustids_all,cost_all,iter_all)
    else
      # save best locally converged solution into a struct
      clust_result =  ClustResult(clust_data,cost,clust_config)
    end
    #TODO save in save file  save_clust_result()
    return clust_result
end

"""
    run_clust_method(data::ClustData;
                  norm_op::String="zscore",
                  norm_scope::String="full",
                  method::String="kmeans",
                  representation::String="centroid",
                  n_clust::Int=5,
                  n_seg::Int=data.T,
                  n_init::Int=100,
                  iterations::Int=300,
                  orig_k_ids::Array{Int,1}=Array{Int,1}(),
                  kwargs...)

method: "kmeans","kmedoids","kmedoids_exact","hierarchical"
representation: "centroid","medoid"
"""
function run_clust_method(data::ClustData;
                  norm_op::String="zscore",
                  norm_scope::String="full",
                  method::String="kmeans",
                  representation::String="centroid",
                  n_clust::Int=5,
                  n_seg::Int=data.T,
                  n_init::Int=100,
                  iterations::Int=300,
                  attribute_weights::Dict{String,Float64}=Dict{String,Float64}(),
                  orig_k_ids::Array{Int,1}=Array{Int,1}(),
                  kwargs...)
    # normalize
    # TODO: implement 0-1 normalization and add as a choice to runclust
    data_norm = z_normalize(data;scope=norm_scope)
    if !isempty(attribute_weights)
      data_norm = attribute_weighting(data_norm,attribute_weights)
    end
    data_norm_merged = ClustDataMerged(data_norm)

    # initialize data arrays (all initial starting points)
    centers = Array{Array{Float64},1}(undef,n_init)
    clustids = Array{Array{Int,1},1}(undef,n_init)
    weights = Array{Array{Float64},1}(undef,n_init)
    cost = Array{Float64,1}(undef,n_init)
    iter = Array{Int,1}(undef,n_init)

    # clustering
    for i = 1:n_init
       # TODO: implement shape based clustering methods
       # function call to the respective function (method + representation)
       fun_name = Symbol("run_clust_"*method*"_"*representation)
       centers[i],weights[i],clustids[i],cost[i],iter[i] =
       @eval $fun_name($data_norm_merged,$n_clust,$iterations;$kwargs...)

       # recalculate centers if medoids is used. Recalculate because medoid is not integrally preserving
      if representation=="medoid"
        centers[i] = resize_medoids(data,centers[i],weights[i])
      end
    end
    # find best. TODO: write as function
    cost_best,ind_mincost = findmin(cost)  # along dimension 2, only store indice

    k_ids=orig_k_ids
    k_ids[findall(orig_k_ids.!=0)]=clustids[ind_mincost]
    # save in merged format as array

    # NOTE if you need clustered data more precise than 8 digits change the following line accordingly
    n_digits_data_round=8 # Gurobi throws warning when rounding errors on order~1e-13 are passed in. Rounding errors occur in clustering of many zeros (e.g. solar).
    clust_data_merged = ClustDataMerged(data.region,data.years,n_clust,data.T,round.(centers[ind_mincost]; digits=n_digits_data_round),data_norm_merged.data_type,weights[ind_mincost],k_ids)
    clust_data = ClustData(clust_data_merged)
        return clust_data, cost_best, centers, weights, clustids, cost, iter
 end

"""
    run_clust(
      data::ClustData,
      n_clust_ar::Array{Int,1};
      norm_op::String="zscore",
      norm_scope::String="full",
      method::String="kmeans",
      representation::String="centroid",
      n_init::Int=100,
      iterations::Int=300,
      save::String="",
      kwargs...)

Run multiple number of clusters k and return an array of results.
This function is a wrapper function around run_clust().
"""
function run_clust(
      data::ClustData,
      n_clust_ar::Array{Int,1};
      norm_op::String="zscore",
      norm_scope::String="full",
      method::String="kmeans",
      representation::String="centroid",
      n_init::Int=100,
      iterations::Int=300,
      save::String="",
      kwargs...
    )
    results_ar = Array{AbstractClustResult,1}(undef,length(n_clust_ar))
    for i=1:length(n_clust_ar)
      results_ar[i] = run_clust(data;norm_op=norm_op,norm_scope=norm_scope,method=method,representation=representation,n_init=n_init,n_clust=n_clust_ar[i],iterations=iterations,save=save,kwargs...)
    end
    return results_ar
end

# supported keyword arguments
sup_kw_args =Dict{String,Array{String}}()
sup_kw_args["region"]=["GER","CA"]
sup_kw_args["opt_problems"]=["battery","gas_turbine"]
sup_kw_args["norm_op"]=["zscore"]
sup_kw_args["norm_scope"]=["full","hourly","sequence"]
sup_kw_args["method+representation"]=["kmeans+centroid","kmeans+medoid","kmedoids+medoid","kmedoids_exact+medoid","hierarchical+centroid","hierarchical+medoid"]#["dbaclust+centroid","kshape+centroid"]

"""
    get_sup_kw_args
Returns supported keyword arguments for clustering function run_clust()
"""
function get_sup_kw_args()
    return sup_kw_args
end



"""
    check_kw_args(region,opt_problems,norm_op,norm_scope,method,representation)
checks if the arguments supplied for run_clust are supported
"""
function check_kw_args(
      norm_op::String,
      norm_scope::String,
      method::String,
      representation::String
    )
    check_ok = true
    error_string = "The following keyword arguments / combinations are not currently supported: \n"
    # norm_op
    if !(norm_op in sup_kw_args["norm_op"])
       check_ok=false
       error_string = error_string * "normalization operation $norm_op is not supported \n"
    end
    # norm_scope
    if !(norm_scope in sup_kw_args["norm_scope"])
       check_ok=false
       error_string = error_string * "normalization scope $norm_scope is not supported \n"
    end
    # method +  representation
    if !(method*"+"*representation in sup_kw_args["method+representation"])
       check_ok=false
       error_string = error_string * "the combination of method $method and representation $representation is not supported \n"
    elseif method == "dbaclust"
       @info("dbaclust can be run in parallel using src/clust_algorithms/runfiles/cluster_gen_dbaclust_parallel.jl")
    elseif method =="kshape"
       check_ok=false
       error_string = error_string * "kshape is implemented in python and should be run individually: src/clust_algorithms/runfiles/cluster_gen_kshape.py \n"
    end
    error_string = error_string * "get_sup_kw_args() provides a list of supported keyword arguments."

    if check_ok
       return true
    else
       error(error_string)
    end
end

"""
    run_clust_kmeans_centroid(data_norm::ClustDataMerged,n_clust::Int,iterations::Int)
"""
function run_clust_kmeans_centroid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int
    )
    centers,weights,clustids,cost,iter =[],[],[],0,0
    # if only one cluster
    if n_clust ==1
        centers_norm = mean(data_norm.data,dims=2) # should be 0 due to normalization
        clustids = ones(Int,size(data_norm.data,2))
        centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids) # need to provide idx in case that sequence-based normalization is used
        cost = sum(pairwise(SqEuclidean(),centers_norm,data_norm.data; dims=2)) #same as sum((seq_norm-repmat(mean(seq_norm,2),1,size(seq,2))).^2)
        iter = 1
    # kmeans() in Clustering.jl is implemented for k>=2
    elseif n_clust==data_norm.K
        clustids = collect(1:data_norm.K)
        centers = undo_z_normalize(data_norm.data,data_norm.mean,data_norm.sdv;idx=clustids) # need to provide idx in case that sequence-based normalization is used
        cost = 0.0
        iter = 1
    else
        results = kmeans(data_norm.data,n_clust;maxiter=iterations)
        # save clustering results
        clustids = results.assignments
        centers_norm = results.centers
        centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)
        cost = results.totalcost
        iter = results.iterations
    end

    weights = calc_weights(clustids,n_clust)

    return centers,weights,clustids,cost,iter

end

"""
    run_clust_kmeans_medoid(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int
    )
"""
function run_clust_kmeans_medoid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int
    )
    centers,weights,clustids,cost,iter =[],[],[],0,0
    # if only one cluster
    if n_clust ==1
        clustids = ones(Int,size(data_norm.data,2))
        centers_norm = calc_medoids(data_norm.data,clustids)
        centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids) # need to provide idx in case that sequence-based normalization is used
        cost = sum(pairwise(SqEuclidean(),centers_norm,data_norm.data; dims=2)) #same as sum((seq_norm-repmat(mean(seq_norm,2),1,size(seq,2))).^2)
        iter = 1
    # kmeans() in Clustering.jl is implemented for k>=2
    elseif n_clust==data_norm.K
        clustids = collect(1:data_norm.K)
        centers = undo_z_normalize(data_norm.data,data_norm.mean,data_norm.sdv;idx=clustids) # need to provide idx in case that sequence-based normalization is used
        cost = 0.0
        iter = 1
    else
        results = kmeans(data_norm.data,n_clust;maxiter=iterations)

        # save clustering results
        clustids = results.assignments
        centers_norm = calc_medoids(data_norm.data,clustids)
        centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)
        cost = calc_SSE(data_norm.data,centers_norm,clustids)
        iter = results.iterations
    end

    weights = calc_weights(clustids,n_clust)

    return centers,weights,clustids,cost,iter

end

"""
    run_clust_kmedoids_medoid(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int
    )
"""
function run_clust_kmedoids_medoid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int
    )

    # TODO: optional in future: pass distance metric as kwargs
    dist = SqEuclidean()
    d_mat=pairwise(dist,data_norm.data, dims=2)
    results = kmedoids(d_mat,n_clust;tol=1e-6,maxiter=iterations)
    clustids = results.assignments
    centers_norm = data_norm.data[:,results.medoids]
    centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)
    cost = results.totalcost
    iter = results.iterations

    weights = calc_weights(clustids,n_clust)

    return centers,weights,clustids,cost,iter
end

"""
    run_clust_kmedoids_exact_medoid(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int;
      gurobi_env=0
    )
"""
function run_clust_kmedoids_exact_medoid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int;
    kmexact_optimizer=0
    )

    (typeof(kmexact_optimizer)==Int) && error("Please provide a kmexact_optimizer (Gurobi Environment). See test file for example")

    # TODO: optional in future: pass distance metric as kwargs
    dist = SqEuclidean()
    results = kmedoids_exact(data_norm.data,n_clust,kmexact_optimizer;_dist=dist)#;distance_type_ar[dist])
    clustids = results.assignments
    centers_norm = results.medoids
    centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)
    cost = results.totalcost
    iter = 1

    weights = calc_weights(clustids,n_clust)

    return centers,weights,clustids,cost,iter
end

"""
    run_clust_hierarchical(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int;
      _dist::SemiMetric = SqEuclidean()
    )

Helper function to run run_clust_hierarchical_centroids and run_clust_hierarchical_medoid
"""
function run_clust_hierarchical(
    data::Array{Float64,2},
    n_clust::Int,
    iterations::Int;
    _dist::SemiMetric = SqEuclidean()
    )

    d_mat=Distances.pairwise(_dist,data; dims=2)
    r=hclust(d_mat,linkage=:ward_presquared)
    clustids = cutree(r,k=n_clust)
    weights = calc_weights(clustids,n_clust)

    return [],weights,clustids,[],1
end

"""
    run_clust_hierarchical_centroid(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int;
      _dist::SemiMetric = SqEuclidean()
    )
"""
function run_clust_hierarchical_centroid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int;
    _dist::SemiMetric = SqEuclidean()
    )
    x,weights,clustids,x,iter= run_clust_hierarchical(data_norm.data,n_clust,iterations;_dist=_dist)
    centers_norm = calc_centroids(data_norm.data,clustids)
    cost = calc_SSE(data_norm.data,centers_norm,clustids)
    centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)

    return centers,weights,clustids,cost,iter
end

"""
    run_clust_hierarchical_medoid(
      data_norm::ClustDataMerged,
      n_clust::Int,
      iterations::Int;
      _dist::SemiMetric = SqEuclidean()
    )
"""
function run_clust_hierarchical_medoid(
    data_norm::ClustDataMerged,
    n_clust::Int,
    iterations::Int;
    _dist::SemiMetric = SqEuclidean()
    )
    ~,weights,clustids,~,iter= run_clust_hierarchical(data_norm.data,n_clust,iterations;_dist=_dist)
    centers_norm = calc_medoids(data_norm.data,clustids)
    cost = calc_SSE(data_norm.data,centers_norm,clustids)
    centers = undo_z_normalize(centers_norm,data_norm.mean,data_norm.sdv;idx=clustids)

    return centers,weights,clustids,cost,iter
end
