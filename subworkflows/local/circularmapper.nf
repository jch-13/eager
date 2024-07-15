//
// Run circularmapper
//

include { FASTQ_ALIGN_BWAALN as FASTQ_ALIGN_BWAALN_ELONGATED  } from '../../subworkflows/nf-core/fastq_align_bwaaln/main'
include { CIRCULARMAPPER_REALIGNSAMFILE                       } from '../../modules/nf-core/circularmapper/realignsamfile/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_REALIGNED          } from '../../modules/nf-core/samtools/index/main'

workflow CIRCULARMAPPER {
    take:
    ch_reference            // channel (mandatory): [ val(meta), path(index), path(reference) ]
    ch_elongated_index      // channel (mandatory): [ val(meta), path(elongated_index) ]
    ch_fastq_reads          // channel (mandatory): [ val(meta), path(reads) ]. subworkImportant: meta REQUIRES single_end` entry!
    val_elongation_factor   // int (mandatory): Elongation factor used for chromosome circularisation

    main:
    ch_versions       = Channel.empty()
    ch_multiqc_files  = Channel.empty()
    ch_realigned_bams = Channel.empty()
    ch_realigned_bais = Channel.empty()
    ch_realigned_csis = Channel.empty()

    // While mapping with BWA will need the elongated reference index, RealignSAMFile apparently does NOT need the elongated reference to be present, only the elongation factor.
    FASTQ_ALIGN_BWAALN_ELONGATED( ch_fastq_reads, ch_elongated_index )
    ch_versions = ch_versions.mix( FASTQ_ALIGN_BWAALN_ELONGATED.out.versions.first() )

    ch_ref_for_realignsamfile = ch_reference
                                .map {
                                    meta, index, reference ->
                                    [ meta, reference ]
                                }
                                .map {
                                    // Prepend a new meta that contains the meta.reference value as the new_meta.reference attribute
                                    addNewMetaFromAttributes( it, "id" , "reference" , false )
                                }

    ch_input_for_realignsamfile = FASTQ_ALIGN_BWAALN_ELONGATED.out.bam
                                .map{
                                    // create meta consistent with rest of MAP workflow
                                    // TODO: Check that the id_index is correctly set and remove the elongation factor suffix if necessary.
                                    meta, bam ->
                                        new_meta = meta + [ reference: meta.id_index ]
                                    [ new_meta, bam ]
                                }
                                .map {
                                    // Prepend a new meta that contains the meta.reference value as the new_meta.reference attribute
                                    addNewMetaFromAttributes( it, "reference" , "reference" , false )
                                }
                                .combine( ch_ref_for_realignsamfile, by: 0 )
                                .multiMap {
                                    ignore_me, meta, bam, ref_meta, ref_fasta ->
                                    bam:   [ metas, bam ]
                                    fasta: [ ref_meta, ref_fasta ]
                                }

    CIRCULARMAPPER_REALIGNSAMFILE( ch_input_for_realignsamfile.bam, ch_input_for_realignsamfile.fasta, val_elongation_factor )
    ch_versions       = ch_versions.mix( CIRCULARMAPPER_REALIGNSAMFILE.out.versions.first() )
    ch_realigned_bams = ch_realigned_bams.mix( CIRCULARMAPPER_REALIGNSAMFILE.out.bam )

    SAMTOOLS_INDEX_REALIGNED( ch_realigned_bams )
    ch_versions       = ch_versions.mix( SAMTOOLS_INDEX_REALIGNED.out.versions.first() )
    ch_realigned_bais = ch_realigned_bais.mix( SAMTOOLS_INDEX_REALIGNED.out.bai )
    ch_realigned_csis = ch_realigned_csis.mix( SAMTOOLS_INDEX_REALIGNED.out.csi )

    emit:
    bam      = ch_realigned_bams // [ val(meta), path(bam) ]
    bai      = ch_realigned_bais // [ val(meta), path(bai) ]
    csi      = ch_realigned_csis // [ val(meta), path(csi) ]
    versions = ch_versions
    mqc      = ch_multiqc_files
}
