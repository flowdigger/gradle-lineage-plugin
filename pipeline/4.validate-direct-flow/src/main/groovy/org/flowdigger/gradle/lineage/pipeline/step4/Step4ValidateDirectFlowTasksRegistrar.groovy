package org.flowdigger.gradle.lineage.pipeline.step4

class Step4ValidateDirectFlowTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step4-validate-direct-flow')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/4.validate-direct-flow"
        ctx.project.tasks.register("collectDirectFlows", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Collect SQL and Java direct flow docs into one canonical document.'
            dependsOn("deriveDirectFlows")
            doFirst {
                ctx.project.file("${ctx.directFlowRoot}/java").mkdirs()
                ctx.project.file("${ctx.validateDirectFlowRoot}/direct-flows.xml").delete()
            }
            style "${stepRoot}/src/main/xsl/collect-direct-flows.xsl"
            input "${stepRoot}/src/main/xml/seed.xml"
            output "${ctx.validateDirectFlowRoot}/direct-flows.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
            param('sql-uri', ctx.toCollectionUri("${ctx.directFlowRoot}/sql", "*.xml"))
            param('java-uri', ctx.toCollectionUri("${ctx.directFlowRoot}/java", "direct-flow.*.xml"))
        }

        ctx.project.tasks.register("validateDirectFlows", ctx.schematronTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: validateDirectFlows'
            dependsOn("deriveDirectFlows", "collectDirectFlows")
            schema "${stepRoot}/src/main/schematron/direct-flow-validation.sch"
            source ctx.project.file("${ctx.validateDirectFlowRoot}/direct-flows.xml")
            outputDir.set(ctx.project.file(ctx.validateDirectFlowRoot))
            failOnError.set(true)
            expandText.set(true)
            onlyIf { !ctx.cfg.skipValidations }
            doFirst {
                logger.lifecycle("Running direct-flow Schematron validation (skipLineageValidations=${ctx.cfg.skipValidations}).")
            }
        }
    }
}
