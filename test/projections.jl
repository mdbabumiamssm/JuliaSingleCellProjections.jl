@testset "Projections" begin
	proj_obs_ind = 1:12:size(counts,2)
	counts_proj = counts[:,proj_obs_ind]

	fl = force_layout(reduced; ndim=3, k=10, rng=StableRNG(408))

	@testset "from" begin
		@test_throws ArgumentError project(counts_proj,transformed)
		t2 = project(counts_proj, transformed; from=counts)
		@test materialize(t2) ≈ materialize(transformed)[:,proj_obs_ind] rtol=1e-3

		fl_proj = project(t2, fl) # automatic from
		@test materialize(fl_proj)≈materialize(fl)[:,proj_obs_ind] rtol=1e-5

		l2 = logtransform(counts_proj)
		@test_throws ArgumentError project(l2,normalized)
		n2 = project(l2,normalized; from=transformed)
		@test size(n2) == (size(normalized,1),size(l2,2)) # TODO: test the result more properly?
	end

	@testset "models" begin
		fl_proj = project(counts_proj, fl.models)
		@test materialize(fl_proj)≈materialize(fl)[:,proj_obs_ind] rtol=1e-5
	end

	@testset "Gene sets subset=$subset_genes rename=$rename_genes shuffle=$shuffle_genes" for subset_genes in (false,true), rename_genes in (false,true), shuffle_genes in (false,true)
		if subset_genes
			gene_ind = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 19, 20, 21, 22, 23, 26, 27, 28, 31, 32, 33, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 47, 48, 49]
		else
			gene_ind = 1:size(expected_sparse,1)
		end
		new_gene_ids = copy(expected_feature_ids)
		rename_genes && (new_gene_ids[1:4:end] .= string.("NEW_", new_gene_ids[1:4:end]))
		ref_var = DataFrame(id=new_gene_ids, feature_type=expected_feature_types)[gene_ind,:]
		ref_mat = expected_sparse[gene_ind,:]

		counts_proj2 = counts[gene_ind,:]
		counts_proj2.var.id .= ref_var.id
		if shuffle_genes
			counts_proj2 = counts_proj2[randperm(StableRNG(498), length(gene_ind)), :]
		end
		empty!(counts_proj2.models)


		@testset "logtransform" begin
			log_mat = simple_logtransform(ref_mat[.!startswith.(ref_var.id,"NEW_"),:], 10_000)
			l = logtransform(counts)
			l_proj2 = project(counts_proj2, l)
			@test materialize(l_proj2) ≈ log_mat
		end

		transformed_proj2 = project(counts_proj2, transformed) # TODO: use me
		# transformed_proj2 = project(counts_proj2, transformed; rtol=1e-9)

		@testset "sctransform" begin
			ref_sct = sctransform(ref_mat, ref_var, params[in(ref_var.id).(params.id),:])
			@test materialize(transformed_proj2) ≈ ref_sct rtol=1e-3
		end

		@testset "normalize" begin
			X = materialize(transformed)
			Y0 = materialize(transformed_proj2)
			missingMask = .!in(transformed_proj2.var.id).(transformed.var.id)

			# expand Y to include all variables from X
			Y = zeros(size(X,1),size(Y0,2))
			Y[indexin(transformed_proj2.var.id,transformed.var.id),:] .= Y0

			c = mean(X; dims=2)
			s = std(X; dims=2)

			# mean-center only
			Yc = Y .- c
			Yc[missingMask, :] .= 0

			n = normalize_matrix(transformed)
			n_proj2 = project(transformed_proj2, n)
			@test materialize(n_proj2) ≈ Yc

			# mean-center and scale
			Ys = Yc./s
			n = normalize_matrix(transformed; scale=true)
			n_proj2 = project(transformed_proj2, n)
			@test materialize(n_proj2) ≈ Ys


			# regress out
			gX = transformed.obs.group
			vm = mean(transformed.obs.value)
			vX = transformed.obs.value .- vm
			gY = transformed_proj2.obs.group
			vY = transformed_proj2.obs.value .- vm # NB: remove mean from reference

			DX = [gX.=="A" gX.=="B" gX.=="C" vX]
			DY = [gY.=="A" gY.=="B" gY.=="C" vY]
			β = X / DX'
			Ycom = Y .- β*DY'

			# zero out reconstructed variables
			Ycom[missingMask, :] .= 0

			Ycom_s = Ycom ./ std(X .- β*DX'; dims=2)

			n = normalize_matrix(transformed, "group", "value")
			n_proj2 = project(transformed_proj2, n)
			@test materialize(n_proj2) ≈ Ycom

			# regress out and scale
			n = normalize_matrix(transformed, "group", "value"; scale=true)
			n_proj2 = project(transformed_proj2, n)
			@test materialize(n_proj2) ≈ Ycom_s
			a = materialize(n_proj2)
			b = Ycom_s

			n = normalize_matrix(transformed, "value"; center=false)
			if subset_genes || rename_genes
				# we cannot reconstruct missing unless center=true
				@test_throws AssertionError project(transformed_proj2, n)
			else
				project(transformed_proj2, n) # no missing so doesn't throw
			end
		end

		# TODO: run normalization with counts - since it needs to reorder (which was otherwise done by transform)
		# @testset "normalize_raw" begin
		# end

		@testset "full" begin
			fl_proj2 = project(counts_proj2, fl)
			@test size(fl_proj2) == size(fl)
		end
	end
end
