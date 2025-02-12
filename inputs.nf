// not on pipeline software:
// the singularity container (e.g. 'rna_seq_1.0') is built in Dockerhub,
// cf. NF configuration files for image version and cache location:
// e.g. may be set to: cacheDir = '/lustre/scratch118/humgen/resources/containers/' 
// cf. available container/software versions at
// https://github.com/wtsi-hgi/nextflow_rna_seq_container

params {

    // input_mode = "from_study_id" // you must choose either "from_study_id" or "from_fastq_csv".
    input_mode = "from_fastq_csv" // you must choose "from_study_id" ; "from_fastq_csv" or "from_fastq"
    
    // if input_mode = "from_study_id":
    input_from_study_id {
	baton_task {
	    run = true
		
	    studies_list = ['5044'] // list of study IDs to process, separted by commas, e.g. ['5591','5855'].
	    // 5044 - CellGen_Characterisation of iPSC-derived macrophages to support functional genomics efforts in cardiovascular disease 5044
	    // http://sequencescape.psd.sanger.ac.uk/studies/5044/information
	}
	iget_cram_task {
	    run = true
	    dropqc = ""
	}
    }
    
    // if input_mode = "from_fastq_csv":  
    input_from_fastq_csv {
	// provide list of paths to fastq (or fastq.gz) files
	// columns samplename and fasq
	// fastq_csv = "${projectDir}/../../inputs/FastQ_files.csv" // if from_study_id run mode // ${projectDir} points to main.nf dir.
		
    	fastq_csv = '/lustre/scratch123/hgi/mdt2/teams/hgi/ip13/data/rnaseq/Run_HUVEC.popov-10.csv'
		run =true
	}
    
    // below are modules/tasks and parameters common to all inputs modes:
    
    crams_to_fastq_gz_task {
		// - 'crams_to_fastq_gz' task merges CRAM files per sample, using samtools, and converts them to fastq.gz
		// - runs on output of 'iget_cram' task
		run = true
		min_reads = 500
    }

    fastqc_task {
		// - this task runs fastqc software on inputs fastq.gz files
		// - runs on output of 'fastqc' task
		run = true
    }
    
    get_egan_id_task {
		// - extracts Egan ID from header of CRAM files.
		// - runs on output of 'crams_to_fastq_gz' task
		// - this will only work if there is only 1 CRAM per sample, needs a fix to handle multiple crams:
		run = false
    }

    // below you can choose to run Salmon and/or STAR aligner:
    
    salmon_aligner {
		salmon_task {
			// - 'salmon' task runs on output of 'crams_to_fastq_gz'
			run = true
			// path to salmon index directory (built with command 'salmon index ...'):
			salmon_index = "/lustre/scratch118/humgen/resources/rna_seq_genomes/salmon_index_Homo_sapiens.GRCh38.cdna.all/"
		}

		salmon_downstream_tasks {
			// below are tasks that run downstream of salmon alignement:
			tximport_task {
				// - 'tximport' task runs on 'salmon' output.
				// - outputs gene/transcript counts matrices.
				run = true
				ensembl_lib = "Ensembl 99 EnsDb" // used by tximport must match used genome version of salmon_index 'salmon' parameter.
			}
			
			// deprecated, might not work:
			merge_salmoncounts_task {
				run = false
			}
			// deprecated, might not work:
			heatmap_task {
				run = false
			}
			// deprecated, might not work:
			deseq2_task {
				run = false
				deseq2_tsv = "${projectDir}/../../inputs/DESeq2.tsv" // ${projectDir} points to main.nf dir.
			}
		}
    }
   
    star_aligner {

		// specify genome GTF file and corresponding STAR index directory (built with command 'STAR --runMode genomeGenerateSTAi ...').
		gtf = "/lustre/scratch118/humgen/resources/rna_seq_genomes/Homo_sapiens.GRCh38.99.gtf"
		// star_index = "/lustre/scratch118/humgen/resources/rna_seq_genomes/star_index_Homo_sapiens.GRCh38.99_75bp/"
			// for STAR 2.7.8a (in version docker pull wtsihgi/rna_seq:1.1):
		star_index = "/lustre/scratch118/humgen/resources/rna_seq_genomes/star2.7.8a_index_Homo_sapiens.GRCh38.99_50bp/"
		
		// this pipeline currently offers 2 alternative ways of running STAR,
		// cf. below 'star_2pass_basic' and 'star_custom_2pass' 
		// you must run at least one of them to get STAR outputs.
		
		star_2pass_basic_task {
			// - runs on output of 'crams_to_fastq_gz' task
			// - runs STAR in a single Nextflow task with '--twopassMode Basic' option:
			run = false
			
			star_tabgenes_matrix_task {
			// - runs on output of 'run_star_2pass_basic' task
			// - uses R script to combined all .ReadsPerGene.out.tab files from STAR into gene count matrix (in tsv format)
			// Those .tab files are gene counts because STAR is run with parameter '--quantMode GeneCounts'
			run = false
			}
			
		}
		
		star_custom_2pass_task {
			// - runs on output of 'crams_to_fastq_gz' task
			// - runs STAR in custom mode with 3 distinct Nextflow tasks:
			//   - 1) first, runs STAR (1st pass) to discover novel splice junctions,
			//   - 2) then merge all junctions,
			//   - 3) finally, run STAR again (2nd pass) but this time use novel junctions as input.
				// choose which task(s) to run:
			run_1st_pass = true
			run_merge_junctions = true
			run_2nd_pass = true
		}

		star_downstream_tasks {
			// - below are tasks that run downstream of STAR alignement.
			// - choose outputs of which star alternative mode should be used downstream:
			downstream_outputs = 'star_custom_2pass' // either 'star_2pass_basic' or 'star_custom_2pass'

			filter_star_aln_rate_task {
				// - runs on output log file from star alignement.
				// - is used as a filter for dowstream stack: checks if global align rate falls below threshold
				run = true
				min_pct_aln  = 5 // align rate minimum (5 means 5%) below which sample star alignement is discarded for downstream tasks.
			}

			featureCounts_task {
			// - runs on output of STAR outputs (bam files) that are not filtered out by 'filter_star_aln_rate' task.
				run = true
			// featureCounts input parameters:
			singleend = true // are reads single- or paired- end?
			unstranded = true // are reads stranded?
			forward_stranded = false // if stranded, are reads forward strandes?
			reverse_stranded = true //    or are reads reverse stranded?
			fcextra = "" // extra parameters passed to featureCounts
			biotypes_header = "${projectDir}/../assets/biotypes_header.txt" 
			
			merge_featureCounts_task {
				// - runs on 'featureCounts' output
				// - runs single execution as it combines/collects 'featureCounts' outputs (from all samples).
				run = true
			}
			}
			
			samtools_index_idxstats_task {
				// - runs on filtered ('filter_star_aln_rate' task) STAR output per sample.
				// -executes 'samtools idxstats' on STAR output bam file (will output a .idxstats file)
				run = true
				map_summary_task {
					// - runs on 'samtools_index_idxstats' output (.idxstats file) per sample.
					//   - Summarise samtools idxstats output even further
					//   - executes custom python script (mito.py) taking .idxstats file as input.
					run = true
					mito_name = 'MT' // used by mapsummary python script. Name of mitochondrial chromosome
				}
			}

			leafcutter_tasks {
				// - implements steps 0. and 1. of
				//   http://davidaknowles.github.io/leafcutter/articles/Usage.html
				//   also linked from: https://github.com/davidaknowles/leafcutter
				bam2junc_regtools_task {
					// - runs on STAR output bam file.
					run = true
				}
				clustering_regtools_task {
					// -  runs on 'bam2junc_regtools' output
					//   combines/collects 'bam2junc_regtools' .junc output files from all samples into a single task.
					run = true
				}
			}
			
			mbv_task {
				// - runs on STAR output bam per sample.
				run = false
				// path to the multi-sample vcf file that contains all samples genotypes (1 chr usually enough).
				mbv_vcf_gz = "/lustre/scratch119/humgen/projects/interval_rna/interval_rna_seq_n5188/genotype_data_mbv_formatting/cohort.chr1.fixed.vcf.gz"
				// path to vcf index file (.csi extension)
				mbv_vcf_gz_csi = "/lustre/scratch119/humgen/projects/interval_rna/interval_rna_seq_n5188/genotype_data_mbv_formatting/cohort.chr1.fixed.vcf.gz.csi"
			}
		}
    }
    
    multiqc_task {
	// multiqc combines STAR, Salmon and fastqc outputs into report.
	run = true
    } 
    
    copy_mode = "rellink" // choose "rellink", "symlink", "move" or "copy" to link output files from work dir into results dir
	copy_mode_fastaq = 'copy'
    // TODO, to test if set to true:
    // not implemented in this pipeline yet:
    // the following are for one-off tasks run after workflow completion to clean-up work dir:
    //// on_complete_uncache_irods_search = false // will remove work dir (effectively un-caching) of Irods search tasks that need to be rerun on next NF run even if completed successfully.
    on_complete_remove_workdir_failed_tasks = false // will remove work dirs of failed tasks (.exitcode file not 0)
    on_complete_remove_workdir_notsymlinked_in_results = false // will remove work dirs of tasks that are not symlinked anywhere in the results dir. This might uncache tasks.. use carefully..
    
}
