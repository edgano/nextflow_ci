//nextflow run ./nextflow_ci/pipelines/main.nf \
//      -c ./nextflow_ci/nextflow.config -c inputs.nf -profile lsf \
//      --nf_ci_loc $PWD -resume

nextflow.enable.dsl=2

// All inputs are read from Nextflow config file "inputs.nf",
//  which is located in upstream Gitlab "nextflow_ci" repo (at same branch name).
// Meaning that if you wish to run pipeline with different parameters,
// you have to edit+commit+push that "inputs.nf" file, then rerun the pipeline.

// import modules that depend on input mode:
include { imeta_study } from './modules/imeta_study.nf'
include { imeta_samples_csv} from './modules/imeta_samples_csv.nf'
include { gsheet_to_csv} from './modules/gsheet_to_csv.nf'

// include workflow common to all input modes:
include { run_from_irods_tsv } from './pipelines/run_from_irods_tsv.nf'

workflow {

    if (params.run_mode == "study_id") {
	imeta_study(Channel.from(params.study_id_mode.input_studies))
	samples_irods_tsv = imeta_study.out.irods_samples_tsv
	work_dir_to_remove = imeta_study.out.work_dir_to_remove }
    
    else if (params.run_mode == "csv_samples_id") {
	i1 = Channel.fromPath(params.csv_samples_id_mode.input_samples_csv)
	i2 = Channel.from(params.csv_samples_id_mode.input_samples_csv_column)
	imeta_samples_csv(i1,i2)
	samples_irods_tsv = imeta_samples_csv.out.irods_samples_tsv
	work_dir_to_remove = imeta_samples_csv.out.work_dir_to_remove }
    
    else if (params.run_mode == "google_spreadsheet") {
	i1 = Channel.from(params.google_spreadsheet_mode.input_gsheet_name)
	i2 = Channel.fromPath(params.google_spreadsheet_mode.input_google_creds)
	i3 = Channel.from(params.google_spreadsheet_mode.output_csv_name)
	gsheet_to_csv(i1,i2,i3)
	i4 = Channel.from(params.google_spreadsheet_mode.input_gsheet_column)
	imeta_samples_csv(gsheet_to_csv.out.samples_csv, i4)
	samples_irods_tsv = imeta_samples_csv.out.irods_samples_tsv
	work_dir_to_remove = imeta_samples_csv.out.work_dir_to_remove.mix(gsheet_to_csv.out.work_dir_to_remove) }

    // common to all input modes:
    run_from_irods_tsv(samples_irods_tsv)

    // list work dirs to remove (because they are Irods searches, so need to always rerun on each NF run):
    // these are removed on workflow.onComplete if (params.on_complete_uncache_irods_search), see below.
    run_from_irods_tsv.out.mix(work_dir_to_remove)
	.filter { it != "dont_remove" }
	.collectFile(name: 'irods_work_dirs_to_remove.csv', newLine: true, sort: true,
		     storeDir:params.outdir)
}

workflow.onError {
    log.info "Pipeline execution stopped with the following message: ${workflow.errorMessage}" }

workflow.onComplete {
    log.info "Pipeline completed at: $workflow.complete"
    log.info "Command line: $workflow.commandLine"
    log.info "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
    
    if (params.on_complete_uncache_irods_search) {
	log.info "You have selected \"on_complete_uncache_irods_search = true\"; will therefore attempt to remove Irods work dirs to forcefully uncache them even if successful."
	if (! file("${params.outdir}/irods_work_dirs_to_remove.csv").isEmpty()) {
	    log.info "file ${params.outdir}/irods_work_dirs_to_remove.csv exists and not empty ..."
	    file("${params.outdir}/irods_work_dirs_to_remove.csv")
		.eachLine {  work_dir ->
		if (file(work_dir).isDirectory()) {
		    log.info "removing work dir $work_dir ..."
		    file(work_dir).deleteDir()   
		} } } }
    
    if (params.on_complete_remove_workdir_failed_tasks) {
	log.info "You have selected \"on_complete_remove_workdir_failed_tasks = true\"; will therefore remove work dirs of all tasks that failed (.exitcode file not 0)."
	// work dir and other paths are hardcoded here ... :
	def proc = "bash ./nextflow_ci/bin/del_work_dirs_failed.sh ${workDir}".execute()
	def b = new StringBuffer()
	proc.consumeProcessErrorStream(b)
	log.info proc.text
	log.info b.toString() }
}

