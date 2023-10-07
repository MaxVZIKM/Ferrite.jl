using Ferrite, SparseArrays

grid = generate_grid(Triangle, (100, 100));

ip_geo = Lagrange{RefTriangle, 1}()
ipu = Lagrange{RefTriangle, 1}()
ipq = RaviartThomas{2,RefTriangle,1}()
qr = QuadratureRule{RefTriangle}(2)
cellvalues = (u=CellValues(qr, ipu, ip_geo), q=CellValues(qr, ipq, ip_geo))

dh = DofHandler(grid)
add!(dh, :u, ipu)
add!(dh, :q, ipq)
close!(dh);

K = create_sparsity_pattern(dh)

ch = ConstraintHandler(dh);

∂Ω = union(
    getfaceset(grid, "left"),
    getfaceset(grid, "right"),
    getfaceset(grid, "top"),
    getfaceset(grid, "bottom"),
);

dbc = Dirichlet(:u, ∂Ω, (x, t) -> 0)
add!(ch, dbc);

close!(ch)

function assemble_element!(Ke::Matrix, fe::Vector, cv::NamedTuple, dr::NamedTuple)
    cvu = cv[:u]
    cvq = cv[:q]
    dru = dr[:u]
    drq = dr[:q]
    n_basefuncs = getnbasefunctions(cvu)
    # Loop over quadrature points
    for q_point in 1:getnquadpoints(cvu)
        # Get the quadrature weight
        dΩ = getdetJdV(cvu, q_point)
        # Loop over test shape functions
        for (iu, Iu) in pairs(dru)
            δu  = shape_value(cvu, q_point, iu)
            ∇δu = shape_gradient(cvu, q_point, iu)
            # Add contribution to fe
            fe[Iu] += δu * dΩ
            # Loop over trial shape functions
            for (jq, Jq) in pairs(drq)
                q = shape_value(cvq, q_point, jq)
                # Add contribution to Ke
                Ke[Iu, Jq] -= (∇δu ⋅ q) * dΩ
            end
        end
        for (iq, Iq) in pairs(drq)
            δq = shape_value(cvq, q_point, iq)
            for (ju, Ju) in pairs(dru)
                ∇u = shape_gradient(cvu, q_point, ju)
                Ke[Iq, Ju] += (δq ⋅ ∇u) * dΩ
            end
            for (jq, Jq) in pairs(drq)
                q = shape_value(cvq, q_point, jq)
                Ke[Iq, Jq] += (δq ⋅ q) * dΩ
            end
        end
    end
    return Ke, fe
end

function assemble_global(cellvalues, K::SparseMatrixCSC, dh::DofHandler)
    # Allocate the element stiffness matrix and element force vector
    dofranges = (u = dof_range(dh, :u), q = dof_range(dh, :q))
    ncelldofs = ndofs_per_cell(dh)
    Ke = zeros(ncelldofs, ncelldofs)
    fe = zeros(ncelldofs)
    # Allocate global force vector f
    f = zeros(ndofs(dh))
    # Create an assembler
    assembler = start_assemble(K, f)
    x = copy(getcoordinates(dh.grid, 1))
    dofs = copy(celldofs(dh, 1))
    # Loop over all cels
    for cellnr in 1:getncells(dh.grid)
        # Reinitialize cellvalues for this cell
        cell = getcells(dh.grid, cellnr)
        getcoordinates!(x, grid, cell)
        celldofs!(dofs, dh, cellnr)
        reinit!(cellvalues[:u], x, cell)
        reinit!(cellvalues[:q], x, cell)
        # Reset to 0
        fill!(Ke, 0)
        fill!(fe, 0)
        # Compute element contribution
        assemble_element!(Ke, fe, cellvalues, dofranges)
        # Assemble Ke and fe into K and f
        assemble!(assembler, dofs, Ke, fe)
    end
    return K, f
end

K, f = assemble_global(cellvalues, K, dh);

apply!(K, f, ch)
u = K \ f;

u_nodes = evaluate_at_grid_nodes(dh, u, :u)
vtk_grid("heat_equation_rt", dh) do vtk
    vtk_point_data(vtk, u_nodes, "u")
end

@show norm(u_nodes)/length(u_nodes)

# This file was generated using Literate.jl, https://github.com/fredrikekre/Literate.jl
