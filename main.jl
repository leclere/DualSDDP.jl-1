# Run dual SDDP on dual of dam1

include("sddp_optim.jl")
include("config.jl")
include("dualutils.jl")
include("mpts2.jl")
include("innerapprox.jl")


# params
SAVE   = false
MAXIT  = 300
NSIMU  = 1000
MCSIZE = 1000
PRIMAL = true
DUAL   = true
COMPARE = false

# OUTER APPROXIMATION
OA = false
# INNER APPROXIMATION
IA = false
# JOINT APPROXIMATION
JA = false

### Build primal problem
model = build_model()
params = getparams()
sddpprimal = SDDPInterface(model, params,
                           SDDP.IterLimit(MAX_ITER),
                           verbose_it=10)
SDDP.init!(sddpprimal)

### Build dual problem
modeldual = buildemptydual(model.noises)
sddpdual = SDDPInterface(modeldual, params,
                         SDDP.IterLimit(MAX_ITER),
                         verbose_it=0)
initdual!(sddpdual)


### SDDP DUAL ####
if DUAL
    ubd = []
    stdd = []
    scen = SDDP.simulate_scenarios(sddpdual.spmodel.noises, MCSIZE)

    # Run 1 combined iteration to init cuts in sddpdual
    for iter in 1:1
        SDDP.iteration!(sddpprimal, sddpdual)
    end
    p0 = SDDP.get_subgradient(sddpprimal.bellmanfunctions[1], X0)


    ### RUN iterations in dual
    lbdual = Float64[]
    println("RUN DUAL SDDP")
    lb = updateinitialstate!(sddpdual, X0)
    tic()
    for iter in 1:MAXIT
        # Update initial costate
        lb = updateinitialstate!(sddpdual, X0)

        # Run forward an backward pass
        SDDP.iteration!(sddpdual)

        # save current iterations
        push!(lbdual, lb)
        (iter % 10 == 0) && displayit(iter, lb)
        #= if iter % UPPER_BOUND == 0 =#
        #=     cost = SDDP.simulate(sddpdual, scen)[1] =#
        #=     push!(ubd, mean(cost)) =#
        #=     push!(stdd, std(cost)) =#
        #= end =#
    end
    texec = toq()
    println("Dual exec time: ", texec)
    SAVE && writecsv("lbdual", lbdual)
    SAVE && writecsv("timedual", sddpdual.stats.exectime)
end


### RUN iterations in primal
if PRIMAL
    ubp = []
    stdp = []
    scen = SDDP.simulate_scenarios(sddpprimal.spmodel.noises, MCSIZE)
    println("RUN PRIMAL SDDP")

    tic()

    for iter in 1:MAXIT
        SDDP.iteration!(sddpprimal)

        if false #iter % UPPER_BOUND == 0
            cost = SDDP.simulate(sddpprimal, scen)[1]
            push!(ubp, mean(cost))
            push!(stdp, std(cost))
        end
        (iter % 10 == 0) && SDDP.reload!(sddpprimal)
    end
    texec = toq()
    println("Primal exec time: ", texec)
    SAVE && writecsv("lbprimal", sddpprimal.stats.lower_bounds)
    SAVE && writecsv("timeprimal", sddpprimal.stats.exectime)
end


### MONTE CARLO ESTIMATION
if OA
    println("RUN OUTER APPROX")
    srand(2713)
    c = @time SDDP.simulate(sddpprimal, NSIMU)[1]
end


### INNER APPROX
if IA
    println("RUN INNER APPROX")
    # Build a new SDDP interface
    sddp= SDDPInterface(model, params,
                        SDDP.IterLimit(MAX_ITER),
                        verbose_it=10)
    # Replace model with inner approx
    init_innermodeler!(sddp, sddpdual.bellmanfunctions)
    #= println(sddp.solverinterface[2]) =#
    srand(2713)
    ci = @time SDDP.simulate(sddp, NSIMU)[1]
end


### JOINT APPROX
if JA
    println("RUN JOINT APPROX")
    # Build a new SDDP interface
    jointcost = Float64[]
    for w in 0:.1:1
        sddp= SDDPInterface(model, params,
                            SDDP.IterLimit(MAX_ITER),
                            verbose_it=10)
        # Replace model with inner approx
        init_jointmodeler!(sddp, sddpdual.bellmanfunctions, sddpprimal.bellmanfunctions, w)
        srand(2713)
        cj = @time SDDP.simulate(sddp, NSIMU)[1]
        push!(jointcost, mean(cj))
    end
end


### RESULTS
lbprimal = sddpprimal.stats.lower_bounds[end]
ubdual = lbdual[end]

println("#"^70)
println("Results --- $MAXIT iterations")
println("-------")
println("Primal LB:\t", lbprimal)
println("Dual UB:\t", ubdual)
println("Gap:\t", abs(lbprimal-ubdual)/lbprimal)
println("Simulation ($NSIMU scenarios)")
OA && println("Monte Carlo (OA):\t", mean(c))
IA && println("Monte Carlo (IA):\t", mean(ci))
JA && println("Monte Carlo (JA):\t", jointcost)

if COMPARE
    @assert lbprimal < ubdual
    p0 = sddpdual.spmodel.initialState
    x0d = SDDP.get_subgradient(sddpdual.bellmanfunctions[1], p0)
    println(X0)
    println(x0d)

    p0p =  SDDP.get_subgradient(sddpprimal.bellmanfunctions[1], X0)
    println(p0)
    println(p0p)
end

if SAVE
    res = zeros(Float64, MAXIT, 6)
    gap = lbdual ./ sddpprimal.stats.lower_bounds[2:end] - 1

    res[:, 1] = sddpprimal.stats.lower_bounds[2:end]
    res[:, 2] = lbdual
    res[:, 3] = gap
    res[:, 4] = cumsum(sddpprimal.stats.exectime[2:end])
    res[:, 5] = cumsum(sddpdual.stats.exectime)
    res[:, 6] = sddpprimal.stats.upper_bounds[2:end]

    writecsv("res/conv_$(MAXIT)_$(NODES)_$(NSTAGES).csv", res)
end
