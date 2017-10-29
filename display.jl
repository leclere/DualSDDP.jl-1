

function dispu(up, nscen, nzones)
    colors = ["k", "r", "b", "g", "c", "m", "y"]
    figure()
    for (ind, i) in enumerate(up*nzones+1:(up+1)*nzones)
        plot(u[:, 1:nscen, i], c=colors[ind])
    end
end


function dispx(nscen, nzones)
    colors = ["k", "r", "b", "g", "c", "m", "y"]
    figure()
    for (ind, i) in enumerate(1:nzones)
        plot(x[:, 1:nscen, i], c=colors[ind])
    end
end


function dispconv(; nscen=1000, ptol=.999, delta=UPPER_BOUND)
    ΔI= delta
    tol = √2 * erfinv(2*ptol - 1)
    ubf = sddpprimal.stats.upper_bounds
    lprim = sddpprimal.stats.lower_bounds

    figure()

    plot(lbdual, c="darkblue", lw=4, label="Dual UB")
    plot(lprim, c="darkred", lw=4, label="Primal LB")
    #= plot(ubf, c="k", lw=.1, label="Forward primal cost") =#


    plot(ΔI:ΔI:MAXIT, ubp, color="k", lw=1.5, label="MC UB")
    plot(ΔI:ΔI:MAXIT, ubp + tol*stdp/√nscen, color="k", lw=1, linestyle=":")
    plot(ΔI:ΔI:MAXIT, ubp - tol*stdp/√nscen, color="k", lw=1, linestyle=":")
    fill_between(ΔI:ΔI:MAXIT, ubp - tol*stdp/√nscen, ubp + tol*stdp/√nscen,
                 color="grey", alpha=.3, label="Confidence ($(100*ptol)%)")


    legend()
    xlabel("Iterations")
    ylim(.99lbprimal, 1.01lbprimal)
end