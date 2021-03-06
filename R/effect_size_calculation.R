#' SNV effect size calculation function
#'
#' Function that determines mutation rate at the gene- and trinucleotide- level
#' and then calculates cancer effect size.
#' Works best on datasets with a large number of tumors, each with a large
#' number of SNV (The \code{deconstructSigs} package, used here to calculate
#' trinucleotide signatues, suggests at least 50 SNV per tumor used in the
#' signature calculation). Requres data to be in hg coordinates, you can use
#' the \code{hg_converter()} function provided with this package to convert
#' from one coordinate system to another.
#'
#' @import deconstructSigs
#' @import dndscv
#' @import parallel
#' @import dplyr
#'
#' @param MAF MAF file with substitution data
#' @param covariate_file Either NULL and uses the \code{dndscv}
#' default covariates, or one of these:  "bladder_pca"  "breast_pca"
#' "cesc_pca" "colon_pca" "esca_pca" "gbm_pca" "hnsc_pca" "kidney_pca" "lihc_pca" "lung_pca" "ov_pca" "pancreas_pca" "prostate_pca" "rectum_pca" "skin_pca"  "stomach_pca"  "thca_pca" "ucec_pca"
#' @param genes_for_effect_size_analysis genes to calculate effect sizes within. If unspecified, defaults to "all".
#' @param sample_ID_column column in MAF with sample ID data
#' @param ref_column column in MAF with reference allele data
#' @param alt_column column in MAF with alternative allele data
#' @param pos_column column in MAF with chromosome nucleotide location data
#' @param chr_column column in MAF with chromosome data
#' @param cores number of cores to use
#' @param tumor_specific_rate_choice weights tumor-specific rates by their relative proportional substitution count (not recommended)
#' @param trinuc_all_tumors Calculates trinucleotide signatures within all tumors (even those with < 50 variants)
#' @param subset_col column in MAF with subset data (e.g., column contains data like "Primary" and "Metastatic" in each row)
#' @param subset_levels_order evolutionary order of events in subset_col. (e.g. c("Primary", "Metastatic")
#'
#' @export





effect_size_SNV <- function(MAF,
                            covariate_file=NULL,
                            sample_ID_column="Unique_patient_identifier",
                            chr_column = "Chromosome",
                            pos_column = "Start_Position",
                            ref_column = "Reference_Allele",
                            alt_column = "Tumor_allele",
                            genes_for_effect_size_analysis = "all",
                            cores = 1,
                            tumor_specific_rate_choice = F,
                            trinuc_all_tumors = T,
                            subset_col = NULL,
                            subset_levels_order = NULL){

  # for auto_subset tests
  # load("../local_work/auto_subset/skcm_maf_data.RData")
  # MAF <- SKCM_maf
  # covariate_file <- "skcm_pca"
  # sample_ID_column="Unique_patient_identifier"
  # chr_column = "Chromosome"
  # pos_column = "Start_Position"
  # ref_column = "Reference_Allele"
  # alt_column = "Tumor_allele"
  # genes_for_effect_size_analysis="all"#c("OTP","KRAS","EGFR","BRAF")
  # cores = 6
  # tumor_specific_rate_choice = F
  # trinuc_all_tumors = T
  # subset_col = "prim_or_met"
  # subset_levels_order = c("primary","metastatic")


  # source("../R/dndscv_wrongRef_checker.R")
  # source("../R/all_in_R_trinucleotide_profile.R")
  # source("../R/selection_intensity_calc_dndscv.R")

  # load("../R/all_gene_trinuc_data.RData")

  # load in MAF

  # MAF <- get(load(MAF_file))
  # MAF <- MAF_file


  message("PLEASE DOWNLOAD v0.1.0, USING INSTRUCTIONS HERE: \nhttps://github.com/Townsend-Lab-Yale/cancereffectsizeR/blob/master/user_guide/cancereffectsizeR_user_guide.md \nOR devtools::install_github(`Townsend-Lab-Yale/cancereffectsizeR@0.1.0` \nOR https://github.com/Townsend-Lab-Yale/cancereffectsizeR/releases/tag/0.1.0
          \nEverything after v0.1.0 is experimental. v0.1.0 is associated with this publication: \nhttps://doi.org/10.1093/jnci/djy168")


  if(length(which(MAF[,pos_column]==150713902))>0){
    MAF <- MAF[-which(MAF[,pos_column]==150713902),]
  }
  if(length(which(MAF[,pos_column]==41123095))>0){
    MAF <- MAF[-which(MAF[,pos_column]==41123095),]
  }


  if(is.null(subset_col)){
    subset_col <- "subset_col"
    MAF$subset_col <- "no_subset"
    MAF$subset_col <- factor(MAF$subset_col,levels = "no_subset")
  }else{
    MAF[,"subset_col"] <- MAF[,subset_col]
    MAF <- MAF[,-which(colnames(MAF)==subset_col)]
    subset_col <- "subset_col"
    MAF[,subset_col] <- factor(x =  MAF[,subset_col], levels=subset_levels_order,ordered = T)
  }


  message("Checking if any reference alleles provided do not match reference genome...")

  MAF <- MAF[,c(sample_ID_column,chr_column,pos_column,ref_column,alt_column,subset_col)]

  reference_alleles <- as.character(BSgenome::getSeq(BSgenome.Hsapiens.UCSC.hg19::Hsapiens, paste("chr",MAF[,chr_column],sep=""),
                                                     strand="+", start=MAF[,pos_column], end=MAF[,pos_column]))

  message(paste(length(which(MAF[,"Reference_Allele"] != reference_alleles))," positions do not match out of ", nrow(MAF), ", (",round(length(which(MAF[,"Reference_Allele"] != reference_alleles))*100/nrow(MAF),4),"%), removing them from the analysis",sep=""))

  MAF <- MAF[-which(MAF[,"Reference_Allele"] != reference_alleles),]

  rm(reference_alleles)

  # MAF <- cancereffectsizeR::wrongRef_dndscv_checker(mutations = MAF) # no longer necessary because of the above step

  # trinuc_data <- cancereffectsizeR::trinuc_profile_function_with_weights(
  #   input_MAF = MAF,
  #   sample_ID_column = sample_ID_column,
  #   chr_column = chr_column,
  #   pos_column = pos_column,
  #   ref_column = ref_column,
  #   alt_column = alt_column)

  # collect the garbage, will do this periodically throughout script
  # because memory tends to fill up with all the function calls
  # important to keep memory usage down because we need low memory per CPU
  # when doing parallelization on the cluster
  gc()

  message("Calculating trinucleotide composition and signatures...")

  # source("R/deconstructSigs_input_preprocess.R") # to be deleted once package is built.

  MAF_input_deconstructSigs_preprocessed <- cancereffectsizeR::deconstructSigs_input_preprocess(MAF = MAF)

  # Need to make sure we are only calculating the selection intensities from tumors in which we are able to calculate a mutation rate
  MAF <- MAF[MAF$Unique_patient_identifier %in% MAF_input_deconstructSigs_preprocessed$Unique_patient_identifier,]

  substitution_counts <- table(MAF_input_deconstructSigs_preprocessed[,sample_ID_column])
  tumors_with_50_or_more <- names(which(substitution_counts>=50))
  tumors_with_less_than_50 <- setdiff(MAF_input_deconstructSigs_preprocessed[,sample_ID_column],tumors_with_50_or_more)

  # relative total substitution rate in all tumors
  median_substitutions <- median(as.numeric(substitution_counts))

  relative_substitution_rate <- substitution_counts/median_substitutions



  trinuc_breakdown_per_tumor <- deconstructSigs::mut.to.sigs.input(mut.ref =
                                                                     MAF_input_deconstructSigs_preprocessed,
                                                                   sample.id = sample_ID_column,
                                                                   chr = chr_column,
                                                                   pos = pos_column,
                                                                   ref = ref_column,
                                                                   alt = alt_column)


  deconstructSigs_trinuc_string <- colnames(trinuc_breakdown_per_tumor)

  rm(MAF_input_deconstructSigs_preprocessed)

  # message("Building trinuc_proportion_matrix")


  trinuc_proportion_matrix <- matrix(data = NA,
                                     nrow = nrow(trinuc_breakdown_per_tumor),
                                     ncol = ncol(trinuc_breakdown_per_tumor))
  rownames(trinuc_proportion_matrix) <- rownames(trinuc_breakdown_per_tumor)
  colnames(trinuc_proportion_matrix) <- colnames(trinuc_breakdown_per_tumor)

  signatures_output_list <- vector(mode = "list",length = length(unique(MAF[,sample_ID_column])))
  names(signatures_output_list) <- unique(MAF[,sample_ID_column])

  if(trinuc_all_tumors==F){
    for(tumor_name in 1:length(tumors_with_50_or_more)){
      signatures_output <- deconstructSigs::whichSignatures(tumor.ref = trinuc_breakdown_per_tumor,
                                                            signatures.ref = signatures.cosmic,
                                                            sample.id = tumors_with_50_or_more[tumor_name],
                                                            contexts.needed = TRUE,
                                                            tri.counts.method = 'exome2genome')

      signatures_output_list[[tumors_with_50_or_more[tumor_name]]] <- list(signatures_output = signatures_output,
                                                                           substitution_count = length(which(MAF[,sample_ID_column] == tumors_with_50_or_more[tumor_name])))


      trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],] <- signatures_output$product/sum( signatures_output$product) #need it to sum to 1.

      # Not all trinuc weights in the cosmic dataset are nonzero for certain signatures
      # This leads to the rare occasion where a certain combination of signatues leads to ZERO
      # rate for particular trinucleotide contexts.
      # True rate is nonzero, as we do see those variants in those tumors, so renormalizing
      # the rates by adding the lowest nonzero rate to all the rates and renormalizing


      if(0 %in% trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],]){
        # finding the lowest nonzero rate
        lowest_rate <- min(trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],
                                                    -which(trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],]==0)])

        # adding it to the rates
        trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],] <- trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],] + lowest_rate

        # renormalizing to 1
        trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],] <-
          trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],] / sum(trinuc_proportion_matrix[tumors_with_50_or_more[tumor_name],])
      }

    }

    # 2. Find nearest neighbor to tumors with < 50 mutations, assign identical weights as neighbor ----
    # message(head(trinuc_proportion_matrix))

    # message("should have printed")

    distance_matrix <- as.matrix(dist(trinuc_breakdown_per_tumor))

    for(tumor_name in 1:length(tumors_with_less_than_50)){
      #find closest tumor that have over 50 mutations
      closest_tumor <- names(sort(distance_matrix[tumors_with_less_than_50[tumor_name],tumors_with_50_or_more]))[1]

      trinuc_proportion_matrix[tumors_with_less_than_50[tumor_name],] <- trinuc_proportion_matrix[closest_tumor,]

      signatures_output_list[[tumors_with_less_than_50[tumor_name]]] <- list(signatures_output = signatures_output_list[[closest_tumor]]$signatures_output, substitution_count = length(which(MAF[,sample_ID_column] == tumors_with_less_than_50[tumor_name])), tumor_signatures_used = closest_tumor)


    }

    rm(distance_matrix)
    # now, trinuc_proportion_matrix has the proportion of all trinucs in every tumor.

    # collect the garbage
    gc()
  }else{
    for(tumor_name in 1:nrow(trinuc_breakdown_per_tumor)){

      signatures_output <- deconstructSigs::whichSignatures(tumor.ref = trinuc_breakdown_per_tumor,
                                                            signatures.ref = signatures.cosmic,
                                                            sample.id = rownames(trinuc_breakdown_per_tumor)[tumor_name],
                                                            contexts.needed = TRUE,
                                                            tri.counts.method = 'exome2genome')

      signatures_output_list[[tumor_name]] <- list(signatures_output = signatures_output,
                                                   substitution_count = length(which(MAF[,sample_ID_column] == rownames(trinuc_breakdown_per_tumor)[tumor_name])))


      trinuc_proportion_matrix[rownames(trinuc_breakdown_per_tumor)[tumor_name],] <- signatures_output$product/sum( signatures_output$product) #need it to sum to 1.

      # Not all trinuc weights in the cosmic dataset are nonzero for certain signatures
      # This leads to the rare occasion where a certain combination of signatues leads to ZERO
      # rate for particular trinucleotide contexts.
      # True rate is nonzero, as we do see those variants in those tumors, so renormalizing
      # the rates by adding the lowest nonzero rate to all the rates and renormalizing


      if(0 %in% trinuc_proportion_matrix[tumor_name,]){
        # finding the lowest nonzero rate
        lowest_rate <- min(trinuc_proportion_matrix[tumor_name,
                                                    -which(trinuc_proportion_matrix[tumor_name,]==0)])

        # adding it to the rates
        trinuc_proportion_matrix[tumor_name,] <- trinuc_proportion_matrix[tumor_name,] + lowest_rate

        # renormalizing to 1
        trinuc_proportion_matrix[tumor_name,] <-
          trinuc_proportion_matrix[tumor_name,] / sum(trinuc_proportion_matrix[tumor_name,])
      }

    }

    # 2. Find nearest neighbor to tumors with < 50 mutations, assign identical weights as neighbor ----
    # message(head(trinuc_proportion_matrix))

    # message("should have printed")
    #
    # distance_matrix <- as.matrix(dist(trinuc_breakdown_per_tumor))
    #
    # for(tumor_name in 1:length(tumors_with_less_than_50)){
    #   #find closest tumor that have over 50 mutations
    #   closest_tumor <- names(sort(distance_matrix[tumors_with_less_than_50[tumor_name],tumors_with_50_or_more]))[1]
    #
    #   trinuc_proportion_matrix[tumors_with_less_than_50[tumor_name],] <- trinuc_proportion_matrix[closest_tumor,]
    #
    #   signatures_output_list[[tumors_with_less_than_50[tumor_name]]] <- list(signatures_output = signatures_output_list[[closest_tumor]]$signatures_output, substitution_count = length(which(MAF[,sample_ID_column] == tumors_with_less_than_50[tumor_name])), tumor_signatures_used = closest_tumor)
    #
    #
    # }
    #
    # rm(distance_matrix)
    # now, trinuc_proportion_matrix has the proportion of all trinucs in every tumor.

    # collect the garbage
    gc()

  }
  message("Calculating gene-level mutation rate...")

  if(is.null(covariate_file)){
    data("covariates_hg19",package = "dndscv")
    genes_in_pca <- rownames(covs)
  }else{
    this_cov_pca <- get(data(list=covariate_file, package="cancereffectsizeR"))
    genes_in_pca <- rownames(this_cov_pca$rotation)
  }

  path_to_library <- dir(.libPaths(),full.names=T)[grep(dir(.libPaths(),full.names=T),pattern="cancereffectsizeR")][1] # find the path to this package


  data("RefCDS_TP53splice",package = "cancereffectsizeR")


  # store dndscv data in a list, split by data subsets
  dndscv_out_list <- vector(mode = "list",length = length(levels(MAF[,subset_col])))
  names(dndscv_out_list) <- levels(MAF[,subset_col])


  # dndscv output for each subset
  for(this_subset in 1:length(dndscv_out_list)){
    dndscv_out_list[[this_subset]] <- dndscv::dndscv(
      mutations = MAF[MAF[,subset_col] == levels(MAF[,subset_col])[this_subset],],
      gene_list = genes_in_pca,
      cv = if(is.null(covariate_file)){ "hg19"}else{ this_cov_pca$rotation},
      refdb = paste(path_to_library,"/data/RefCDS_TP53splice.RData",sep=""))
  }

  RefCDS_our_genes <- RefCDS[which(sapply(RefCDS, function(x) x$gene_name) %in% dndscv_out_list[[1]]$genemuts$gene_name)]


  data("gene_trinuc_comp", package = "cancereffectsizeR")
  names(gene_trinuc_comp) <- sapply(RefCDS, function(x) x$gene_name)



  # collect the garbage
  gc()




  mutrates_list <- vector(mode = "list", length = length(levels(MAF[,subset_col])))
  names(mutrates_list) <- levels(MAF[,subset_col])
  dndscv_pq_list <- vector(mode="list", length = length(levels(MAF[,subset_col])))
  names(dndscv_pq_list) <- levels(MAF[,subset_col])


  for(this_subset in 1:length(mutrates_list)){

    number_of_tumors_in_this_subset <- length(unique(MAF[MAF[,subset_col] == levels(MAF[,subset_col])[this_subset],sample_ID_column]))


    if(dndscv_out_list[[this_subset]]$nbreg$theta>1){
      mutrates_list[[this_subset]] <- ((dndscv_out_list[[this_subset]]$genemuts$n_syn + dndscv_out_list[[this_subset]]$nbreg$theta - 1)/(1+(dndscv_out_list[[this_subset]]$nbreg$theta/dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv))/sapply(RefCDS_our_genes, function(x) colSums(x$L)[1]))/number_of_tumors_in_this_subset
    }else{
      mutrates_list[[this_subset]] <- rep(NA,length(dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv))

      syn_sites <- sapply(RefCDS_our_genes, function(x) colSums(x$L)[1])

      for(i in 1:length(mutrates_list[[this_subset]])){
        if( dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv[i] >  ((dndscv_out_list[[this_subset]]$genemuts$n_syn[i] + dndscv_out_list[[this_subset]]$nbreg$theta - 1)/(1+(dndscv_out_list[[this_subset]]$nbreg$theta/dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv[i])))){
          mutrates_list[[this_subset]][i] <- (dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv[i]/syn_sites[i])/number_of_tumors_in_this_subset
        }else{
          mutrates_list[[this_subset]][i] <- (((dndscv_out_list[[this_subset]]$genemuts$n_syn[i] + dndscv_out_list[[this_subset]]$nbreg$theta - 1)/(1+(dndscv_out_list[[this_subset]]$nbreg$theta/dndscv_out_list[[this_subset]]$genemuts$exp_syn_cv[i])))/syn_sites[i])/number_of_tumors_in_this_subset
        }

      }
    }
    names(mutrates_list[[this_subset]]) <- dndscv_out_list[[this_subset]]$genemuts$gene_name



    dndscv_pq_list[[this_subset]] <- dndscv_out_list[[this_subset]]$sel_cv
    dndscv_pq_list[[this_subset]]$gene <- dndscv_pq_list[[this_subset]]$gene_name
    dndscv_pq_list[[this_subset]]$p <- dndscv_pq_list[[this_subset]]$pallsubs_cv
    dndscv_pq_list[[this_subset]]$q <- dndscv_pq_list[[this_subset]]$qallsubs_cv

  }

  # 4. Assign genes to MAF ----
  # keeping assignments consistent with dndscv, where possible

  MAF$Gene_name <- NA
  MAF$unsure_gene_name <- F

  MAF_ranges <- GenomicRanges::GRanges(seqnames = MAF[,chr_column], ranges = IRanges::IRanges(start=MAF[,pos_column],end = MAF[,pos_column]))

  # data("refcds_hg19", package="dndscv") # load in gr_genes data

  # first, find overlaps

  gene_name_overlaps <- GenomicRanges::findOverlaps(query = MAF_ranges,subject = gr_genes, type="any", select="all")

  # duplicate any substitutions that matched two genes
  overlaps <- as.matrix(gene_name_overlaps)

  matched_ol <- which(1:nrow(MAF) %in% overlaps[,1])
  unmatched_ol <- setdiff(1:nrow(MAF), matched_ol)

  MAF_matched <- MAF[matched_ol,]

  MAF_ranges <- GenomicRanges::GRanges(seqnames = MAF_matched[,chr_column], ranges = IRanges::IRanges(start=MAF_matched[,pos_column],end = MAF_matched[,pos_column]))

  gene_name_overlaps <- as.matrix(GenomicRanges::findOverlaps(query = MAF_ranges,subject = gr_genes, type="any", select="all"))

  MAF_matched <- MAF_matched[gene_name_overlaps[,1],] #expand the multi-matches
  MAF_matched$Gene_name <- gr_genes$names[gene_name_overlaps[,2]]# assign the multi-matches


  MAF_unmatched <- MAF[unmatched_ol,]



  # MAF_expanded <- MAF[overlaps[,1],] #this gets rid of unmatched subs, though...

  # search out the unmatched remainder

  MAF_ranges <- GenomicRanges::GRanges(seqnames = MAF_unmatched[,chr_column], ranges = IRanges::IRanges(start=MAF_unmatched[,pos_column],end = MAF_unmatched[,pos_column]))

  gene_name_matches <- GenomicRanges::nearest(x = MAF_ranges, subject = gr_genes,select=c("all"))


  # take care of single hits
  single_choice <- as.numeric(names(table(S4Vectors::queryHits(gene_name_matches)))[which(table(S4Vectors::queryHits(gene_name_matches))==1)])

  MAF_unmatched$Gene_name[single_choice] <- gr_genes$names[S4Vectors::subjectHits(gene_name_matches)[which(S4Vectors::queryHits(gene_name_matches) %in% single_choice)]]



  # multi_choice <- as.numeric(names(table(S4Vectors::queryHits(gene_name_matches)))[which(table(S4Vectors::queryHits(gene_name_matches))>1)])


  # Then, assign rest to the closest gene

  multi_choice <- as.numeric(names(table(S4Vectors::queryHits(gene_name_matches)))[which(table(S4Vectors::queryHits(gene_name_matches))>1)])

  all_possible_names <- gr_genes$names[S4Vectors::subjectHits(gene_name_matches)]
  query_spots <- S4Vectors::queryHits(gene_name_matches)




  for(i in 1:length(multi_choice)){
    # first, assign if the nearest happened to be within the GenomicRanges::findOverlaps() and applicable to one gene
    if(length(which(queryHits(gene_name_matches) == multi_choice[i])) == 1){

      MAF_unmatched[multi_choice[i],"Gene_name"] <- gr_genes$names[subjectHits(gene_name_matches)[which(queryHits(gene_name_matches) == multi_choice[i])]]

    }else{

      genes_for_this_choice <- all_possible_names[which(query_spots==multi_choice[i])]

      if(any( genes_for_this_choice %in% names(mutrates_list[[1]]), na.rm=TRUE )){
        MAF_unmatched$Gene_name[multi_choice[i]] <- genes_for_this_choice[which( genes_for_this_choice %in% names(mutrates_list[[1]]) )[1]]
      }else{
        MAF_unmatched$Gene_name[multi_choice[i]] <- "Indeterminate"
      }
    }
  }

  MAF_unmatched$unsure_gene_name <- T

  MAF <- rbind(MAF_matched,MAF_unmatched)

  rm(MAF_unmatched);rm(MAF_matched);gc()



  # 5. For each substitution, calculate the gene- and tumor- and mutation-specific mutation rate----

  # data("gene_trinuc_comp", package = "cancereffectsizeR")
  data("AA_mutation_list", package = "cancereffectsizeR")


  MAF <- MAF[which(MAF$Gene_name %in% names(mutrates_list[[1]])),]
  MAF <- MAF[which(MAF$Reference_Allele %in% c("A","T","C","G") & MAF$Tumor_allele %in% c("A","T","C","G")),]

  dndscvout_annotref <- NULL
  for(this_subset in 1:length(dndscv_out_list)){
    dndscvout_annotref <- rbind(dndscvout_annotref,dndscv_out_list[[this_subset]]$annotmuts)
  }

  dndscvout_annotref <- dndscvout_annotref[which(dndscvout_annotref$ref %in% c("A","T","G","C") & dndscvout_annotref$mut %in% c("A","T","C","G")),]

  # assign strand data
  strand_data <- sapply(RefCDS_our_genes, function(x) x$strand)
  names(strand_data) <- sapply(RefCDS_our_genes, function(x) x$gene_name)
  strand_data[which(strand_data==-1)] <- "-"
  strand_data[which(strand_data==1)] <- "+"

  MAF$strand <- strand_data[MAF$Gene_name]



  MAF$triseq <- as.character(BSgenome::getSeq(BSgenome.Hsapiens.UCSC.hg19::Hsapiens, paste("chr",MAF$Chromosome,sep=""),
                                              strand=MAF$strand, start=MAF$Start_Position-1, end=MAF$Start_Position+1))

  MAF$unique_variant_ID <- paste(MAF$Gene_name,MAF$Chromosome,MAF$Start_Position, MAF$Tumor_allele)
  dndscvout_annotref$unique_variant_ID <- paste(dndscvout_annotref$gene,dndscvout_annotref$chr, dndscvout_annotref$pos, dndscvout_annotref$mut)


  MAF$is_coding <- MAF$unique_variant_ID %in% dndscvout_annotref$unique_variant_ID[which(dndscvout_annotref$impact != "Essential_Splice")]

  # Assign trinucleotide context data (for use with non-coding variants)
  MAF$Tumor_allele_correct_strand <- MAF$Tumor_allele
  MAF$Tumor_allele_correct_strand[which(MAF$strand=="-")] <- toupper(seqinr::comp(MAF$Tumor_allele_correct_strand[which(MAF$strand=="-")]))

  data("trinuc_translator", package="cancereffectsizeR")

  MAF$trinuc_dcS <- trinuc_translator[paste(MAF$triseq,":",MAF$Tumor_allele_correct_strand,sep=""),"deconstructSigs_format"]

  # Assign coding variant data

  dndscv_coding_unique <- dndscvout_annotref[!duplicated(dndscvout_annotref$unique_variant_ID),]

  rownames(dndscv_coding_unique) <- dndscv_coding_unique$unique_variant_ID
  MAF$nuc_variant <- NA
  MAF$coding_variant <- NA
  MAF[,c("nuc_variant","coding_variant")] <- dndscv_coding_unique[MAF$unique_variant_ID,c("ntchange","aachange")]
  MAF[which(MAF$coding_variant=="-"),"coding_variant"] <- NA
  MAF[which(MAF$nuc_variant=="-"),"nuc_variant"] <- NA

  MAF$nuc_position  <- as.numeric(gsub("\\D", "", MAF$nuc_variant))
  MAF$codon_pos <- (MAF$nuc_position %% 3)
  MAF$codon_pos[which(MAF$codon_pos==0)] <- 3


  MAF$amino_acid_context <- as.character(
    BSgenome::getSeq(BSgenome.Hsapiens.UCSC.hg19::Hsapiens, paste(
      "chr",MAF$Chromosome,sep=""),
      strand=MAF$strand, start=MAF$Start_Position-3, end=MAF$Start_Position+3))

  ref_cds_genes <- sapply(RefCDS_our_genes, function(x) x$gene_name)
  names(RefCDS_our_genes) <- ref_cds_genes

  MAF$amino_acid_context[which(MAF$codon_pos==1)] <-
    substr(MAF$amino_acid_context[which(MAF$codon_pos==1)],3,7)

  MAF$amino_acid_context[which(MAF$codon_pos==2)] <-
    substr(MAF$amino_acid_context[which(MAF$codon_pos==2)],2,6)

  MAF$amino_acid_context[which(MAF$codon_pos==3)] <-
    substr(MAF$amino_acid_context[which(MAF$codon_pos==3)],1,5)

  MAF$next_to_splice <- F
  for(i in 1:nrow(MAF)){
    if(any(abs(MAF$Start_Position[i] - RefCDS_our_genes[[MAF$Gene_name[i]]]$intervals_cds) <= 3)){

      MAF$next_to_splice[i] <- T

    }
  }


  # names(gene_trinuc_comp) <- ref_cds_genes

  MAF$unique_variant_ID_AA <- NA

  MAF[which(MAF$is_coding==T),"unique_variant_ID_AA"] <- MAF[which(MAF$is_coding==T),"coding_variant"]
  MAF[which(MAF$is_coding==F),"unique_variant_ID_AA"] <- MAF[which(MAF$is_coding==F),"unique_variant_ID"]

  substrRight <- function(x, n){
    substr(x, nchar(x)-n+1, nchar(x))
  }

  MAF$coding_variant_AA_mut <-  substrRight(x = MAF$coding_variant,n=1)

  data("AA_translations", package="cancereffectsizeR") # from cancereffectsizeR

  AA_translations_unique <- AA_translations[!duplicated(AA_translations$AA_letter),]
  rownames(AA_translations_unique) <- as.character(AA_translations_unique$AA_letter)

  MAF$coding_variant_AA_mut <- as.character(AA_translations_unique[MAF$coding_variant_AA_mut,"AA_short"])

  # source("R/mutation_finder.R")
  # source("R/mutation_rate_calc.R")

  rm(dndscv_coding_unique);rm(dndscvout_annotref);gc()

  message("Calculating selection intensity...")



  # tumors <- unique(MAF$Unique_patient_identifier)




  tumors <- matrix(data = NA,nrow = length(unique(MAF[,sample_ID_column])),ncol=1)
  colnames(tumors) <- c("subset")
  rownames(tumors) <- unique(MAF[,sample_ID_column])
  for(tumor in unique(MAF[,sample_ID_column])){
   tumors[tumor,1] <- MAF[which(MAF[,sample_ID_column]==tumor)[1] ,subset_col]
  }


  if(all(genes_for_effect_size_analysis=="all")){
    genes_to_analyze <- unique(MAF$Gene_name)
  }else{
    genes_to_analyze <-
      genes_for_effect_size_analysis[genes_for_effect_size_analysis %in% unique(MAF$Gene_name)]
  }

  selection_results <- vector("list",length = length(genes_to_analyze))
  names(selection_results) <- genes_to_analyze

  get_gene_results <- function(gene_to_analyze) {

    these_mutation_rates <-
      cancereffectsizeR::mutation_rate_calc(
        this_MAF = subset(MAF,
                          Gene_name==gene_to_analyze &
                            Reference_Allele %in% c("A","T","G","C") &
                            Tumor_allele %in% c("A","T","G","C")),
        gene = gene_to_analyze,
        gene_mut_rate = mutrates_list,
        trinuc_proportion_matrix = trinuc_proportion_matrix,
        gene_trinuc_comp = gene_trinuc_comp,
        RefCDS = RefCDS_our_genes,
        relative_substitution_rate=relative_substitution_rate,
        tumor_specific_rate=tumor_specific_rate_choice,
        tumor_subsets = tumors,subset_col=subset_col)

    # these_selection_results <- matrix(
    #   nrow=ncol(these_mutation_rates$mutation_rate_matrix), ncol=5,data=NA)
    # rownames(these_selection_results) <- colnames(these_mutation_rates$mutation_rate_matrix)
    # colnames(these_selection_results) <- c(
    #   "variant","selection_intensity","unsure_gene_name","variant_freq","unique_variant_ID")

    # data frame with a list of selection results corresponding to subsets.

    these_selection_results <- dplyr::tibble(variant = colnames(these_mutation_rates$mutation_rate_matrix),
                                          selection_intensity = vector(mode = "list",
                                                                         length = ncol(these_mutation_rates$mutation_rate_matrix)),
                                          unsure_gene_name=NA,
                                          variant_freq=vector(mode = "list",
                                                                length = ncol(these_mutation_rates$mutation_rate_matrix)),
                                          unique_variant_ID=NA)
    # rownames(these_selection_results) <- colnames(these_mutation_rates$mutation_rate_matrix)


    # these_selection_results <- as_tibble(these_selection_results)
    for(j in 1:nrow(these_selection_results)){



      these_selection_results[j,c("selection_intensity")][[1]] <-
        list(cancereffectsizeR::optimize_gamma(
            MAF_input=subset(MAF,
                             Gene_name==gene_to_analyze &
                               Reference_Allele %in% c("A","T","G","C") &
                               Tumor_allele %in% c("A","T","G","C")),
            all_tumors=tumors,
            gene=gene_to_analyze,
            variant=colnames(these_mutation_rates$mutation_rate_matrix)[j],
            specific_mut_rates=these_mutation_rates$mutation_rate_matrix))
      names(these_selection_results[j,c("selection_intensity")][[1]][[1]]) <- levels(MAF[,subset_col])

      freq_vec <- NULL
      for(this_level in 1:length(these_mutation_rates$variant_freq)){
      freq_vec <- c(freq_vec,these_mutation_rates$variant_freq[[this_level]][as.character(these_selection_results[j,"variant"])])
      }
      these_selection_results[j,"variant_freq"][[1]] <- list(freq_vec)
      names(these_selection_results[j,"variant_freq"][[1]][[1]]) <- levels(MAF[,subset_col])
    }

    these_selection_results[,"unsure_gene_name"] <- these_mutation_rates$unsure_genes_vec

    these_selection_results[,"unique_variant_ID"] <- these_mutation_rates$unique_variant_ID



    print(gene_to_analyze)

    return(list(gene_name=gene_to_analyze,RefCDS_our_genes[[gene_to_analyze]]$gene_id,selection_results=these_selection_results))

  }

  selection_results <- parallel::mclapply(genes_to_analyze, get_gene_results, mc.cores = cores)





  return(list(selection_output=selection_results,
              mutation_rates=mutrates_list,
              trinuc_data=list(trinuc_proportion_matrix=trinuc_proportion_matrix,
                               signatures_output=signatures_output_list),
              dndscvout=dndscv_out_list,
              MAF=MAF))

}



