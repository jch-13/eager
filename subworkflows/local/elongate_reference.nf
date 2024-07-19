//
// Elongate a reference genome by circularising the target sequence by a given elongation factor.
//

include { GUNZIP as GUNZIP_ELONGATED_FASTA    } from '../../modules/nf-core/gunzip/main'
include { CIRCULARMAPPER_CIRCULARGENERATOR    } from '../../modules/nf-core/circularmapper/circulargenerator/main'
include { BWA_INDEX as BWA_INDEX_CIRCULARISED } from '../../modules/nf-core/bwa/index/main'
// TODO Check that the unzipping correctly overwrites the zipped fasta file, and that the emitted channel is constructed correctly.
// TODO Currently, nothing seems to get dumped in the emission channel, so some join must be off.

workflow ELONGATE_REFERENCE {
    take:
    ch_reference            // [ meta, fasta, fai, dict, mapindex ]
    ch_elongated_reference  // [ meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ]

    main:
    ch_versions           = Channel.empty()
    ch_multiqc_files      = Channel.empty()
    ch_circular_reference = Channel.empty()
    ch_elongated_unzipped = Channel.empty()

    // Check if the provided elongated reference is gzipped, and if so, unzip it.
    ch_elongated_branches = ch_elongated_reference
                            .branch {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ->
                                    for_gunzip: circularmapper_elongated_fasta != '' && circularmapper_elongated_fasta.extension == "gz"
                                    skip_gunzip: true
                            }

    ch_elongated_for_gunzip = ch_elongated_branches.for_gunzip
                            .map {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ->
                                    [ meta, circularmapper_elongated_fasta ]
                            }

    GUNZIP_ELONGATED_FASTA( ch_elongated_for_gunzip )
    ch_versions = ch_versions.mix( GUNZIP_ELONGATED_FASTA.out.versions.first() )

    ch_elongated_unzipped = ch_elongated_reference
                            .join( GUNZIP_ELONGATED_FASTA.out.gunzip )
                            .dump(tag: 'unzipped_fasta')
                            .map {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai, unzipped_fasta ->
                                    def final_fasta = unzipped_fasta ?: circularmapper_elongated_fasta
                                    [ meta, circular_target, unzipped_fasta, circularmapper_elongated_fai ]
                            }

    /*
        Check what fasta files we have.
        There are four options:
            1. Elongated reference with index (ignore circular target) -> Pass through
            2. Elongated reference without index (ignore circular target) -> Index and emit
            3. No elongated reference, but circular target -> Elongate, index and emit.
            4. None of the above -> Throw error and stop execution during parameter validation
    */

    ch_circulargenerator_input = ch_elongated_unzipped
                            .branch{
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ->
                                        ready:            circularmapper_elongated_fasta != "" && circularmapper_elongated_fai != ""
                                        needs_index:      circularmapper_elongated_fasta != "" && circularmapper_elongated_fai == ""
                                        needs_elongation: circularmapper_elongated_fasta == "" && circular_target != ""
                            }

    // Elongate references that need it
    // Join the original references to the branch of needs_elongation, to get the original fasta files, and elongate them.
    ch_references_to_elongate = ch_circulargenerator_input.needs_elongation
                            .join( ch_reference )
                            .multiMap {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai, fasta, fai, dict, mapindex ->

                                    def elongation_factor = params.mapping_circularmapper_elongation_factor

                                    fasta:              [ meta, fasta ]
                                    elongation_factor : [ meta, elongation_factor ]
                                    target:             [ meta, circular_target ]
                            }

    CIRCULARMAPPER_CIRCULARGENERATOR(
        ch_references_to_elongate.fasta,
        ch_references_to_elongate.elongation_factor,
        ch_references_to_elongate.target
    )
    ch_versions = ch_versions.mix( CIRCULARMAPPER_CIRCULARGENERATOR.out.versions.first() )

    // Collect newly generated circular references and provided ones without an index, and index them.
    ch_input_for_circular_indexing = ch_circulargenerator_input.needs_index
                            .map {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ->
                                    [ meta, circularmapper_elongated_fasta ]
                            }
                            .mix( CIRCULARMAPPER_CIRCULARGENERATOR.out.fasta )

    BWA_INDEX_CIRCULARISED(ch_input_for_circular_indexing)
    ch_versions = ch_versions.mix( BWA_INDEX_CIRCULARISED.out.versions.first() )

    ch_indexed_references = ch_input_for_circular_indexing
                            .join( BWA_INDEX_CIRCULARISED.out.index )

    // Then put all the indexed elongated references together, replace any zipped ones with the unzipped version, and emit them
    ch_circular_reference = ch_circulargenerator_input.ready.dump(tag:"ready", pretty:true)
                            .map {
                                meta, circular_target, circularmapper_elongated_fasta, circularmapper_elongated_fai ->
                                    [ meta, circularmapper_elongated_fasta, circularmapper_elongated_fai ]
                            }
                            .mix( ch_indexed_references.dump(tag:"indexed", pretty: true) )
                            .dump(tag: 'circular_reference')

    emit:
    circular_reference = ch_circular_reference // [ meta, circular_target, fasta, fai ]
    versions           = ch_versions
    mqc                = ch_multiqc_files
}
