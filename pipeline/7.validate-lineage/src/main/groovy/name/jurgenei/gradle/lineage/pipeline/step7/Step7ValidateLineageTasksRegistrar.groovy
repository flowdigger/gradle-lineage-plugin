package name.jurgenei.gradle.lineage.pipeline.step7

import org.gradle.api.GradleException

import java.io.BufferedInputStream
import java.io.FileInputStream

class Step7ValidateLineageTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step7-validate-lineage')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/7.validate-lineage"
        def stitchedLineageFile = ctx.project.file("${ctx.stitchRoot}/stitched-lineage.xml")
        ctx.project.tasks.register("carryAppXirToValidation", ctx.copyTaskClass) {
            group = 'lineage'
            description = 'Carry per-processor app lineage artifacts from stitch phase.'
            dependsOn("stitchLineage")
            from("${ctx.stitchRoot}/lineage/app/xir")
            into("${ctx.validateRoot}/lineage/app/xir")
            include("**/*.xir")
        }

        ctx.project.tasks.register("validateStitchLinkReferences") {
            group = 'lineage'
            description = 'Validate stitch-link direct-flow references with streaming XML scan.'
            dependsOn("stitchLineage")
            inputs.file(stitchedLineageFile)
            outputs.file(ctx.project.file("${ctx.validateRoot}/stitch-link-reference-validation.marker"))
            onlyIf { !ctx.cfg.skipValidations }
            doLast {
                if (!stitchedLineageFile.exists()) {
                    throw new GradleException("Missing stitched lineage input for stitch-link validation: ${stitchedLineageFile}")
                }

                def xmlInputFactory = javax.xml.stream.XMLInputFactory.newFactory()
                xmlInputFactory.setProperty(javax.xml.stream.XMLInputFactory.IS_NAMESPACE_AWARE, false)

                def directFlowIds = new HashSet<String>(131072)
                def collectReader = xmlInputFactory.createXMLStreamReader(new BufferedInputStream(new FileInputStream(stitchedLineageFile)))
                try {
                    while (collectReader.hasNext()) {
                        if (collectReader.next() == javax.xml.stream.XMLStreamConstants.START_ELEMENT && collectReader.localName == 'stitched-flow') {
                            def directFlowId = collectReader.getAttributeValue(null, 'direct-flow-id')
                            if (directFlowId != null && !directFlowId.isBlank()) {
                                directFlowIds.add(directFlowId)
                            }
                        }
                    }
                } finally {
                    collectReader.close()
                }

                def missingFrom = 0
                def missingTo = 0
                def missingFromSamples = []
                def missingToSamples = []
                def sampleLimit = 5

                def validateReader = xmlInputFactory.createXMLStreamReader(new BufferedInputStream(new FileInputStream(stitchedLineageFile)))
                try {
                    while (validateReader.hasNext()) {
                        if (validateReader.next() != javax.xml.stream.XMLStreamConstants.START_ELEMENT || validateReader.localName != 'stitch-link') {
                            continue
                        }

                        def fromDirectFlowId = validateReader.getAttributeValue(null, 'from-direct-flow-id')
                        if (fromDirectFlowId == null || fromDirectFlowId.isBlank() || !directFlowIds.contains(fromDirectFlowId)) {
                            missingFrom++
                            if (missingFromSamples.size() < sampleLimit) {
                                missingFromSamples << (fromDirectFlowId ?: '<missing>')
                            }
                        }

                        def toDirectFlowId = validateReader.getAttributeValue(null, 'to-direct-flow-id')
                        if (toDirectFlowId == null || toDirectFlowId.isBlank() || !directFlowIds.contains(toDirectFlowId)) {
                            missingTo++
                            if (missingToSamples.size() < sampleLimit) {
                                missingToSamples << (toDirectFlowId ?: '<missing>')
                            }
                        }
                    }
                } finally {
                    validateReader.close()
                }

                if (missingFrom > 0 || missingTo > 0) {
                    throw new GradleException(
                            "stitch-link direct-flow reference validation failed: " +
                                    "missing from-direct-flow-id=${missingFrom} samples=${missingFromSamples}; " +
                                    "missing to-direct-flow-id=${missingTo} samples=${missingToSamples}"
                    )
                }

                def markerFile = ctx.project.file("${ctx.validateRoot}/stitch-link-reference-validation.marker")
                markerFile.parentFile.mkdirs()
                markerFile.text = "ok\n"
            }
        }

        ctx.project.tasks.register("validateLineage", ctx.schematronTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: validateLineage'
            dependsOn("stitchLineage")
            dependsOn("validateStitchLinkReferences")
            schema "${stepRoot}/src/main/schematron/validate-lineage.sch"
            source stitchedLineageFile
            outputDir.set(ctx.project.file(ctx.validateRoot))
            failOnError.set(true)
            expandText.set(true)
            workers.set(4)
            onlyIf { !ctx.cfg.skipValidations }
            doFirst {
                logger.lifecycle("Running stitched-lineage Schematron validation (skipLineageValidations=${ctx.cfg.skipValidations}).")
            }
        }
    }
}
