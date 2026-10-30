package name.jurgenei.gradle.lineage.pipeline.step5

import org.gradle.api.GradleException

class Step5MergeTasksRegistrar {
    static void register(def ctx) {
        def observeStepRoot = ctx.project.findProject(':pipeline:step2-observe')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/2.observe"
        def stepRoot = ctx.project.findProject(':pipeline:step5-merge')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/5.merge"
        if (ctx.cfg.sqlEnabled && ctx.sqlSourceSets.size() > 1) {
            throw new GradleException("Merge phase currently supports one SQL sourceSet. Found: ${ctx.sqlSourceSets*.name}")
        }
        if (ctx.cfg.sqlEnabled) {
            ctx.schemaNames.each { schema ->
                def schemaCap = schema.capitalize()
                ctx.project.tasks.register("sqlTableIndex${schemaCap}", ctx.xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL table index for ${schema}."
                    style "${observeStepRoot}/src/main/xsl/table-procedure-indexer.xsl"
                    input "${observeStepRoot}/src/main/xml/table-index.xml"
                    output "${ctx.sqlIndexRoot}/table-index.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('input-uri', ctx.project.file("${ctx.observeRoot}/sql/${ctx.sqlPrimarySourceSet}/${schema}").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
                    param('schema-name', schema)
                }

                ctx.project.tasks.register("sqlProcedureIndex${schemaCap}", ctx.xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL procedure index for ${schema}."
                    style "${observeStepRoot}/src/main/xsl/index-procedures.xsl"
                    input "${observeStepRoot}/src/main/xml/procedure-index.xml"
                    output "${ctx.sqlIndexRoot}/procedure.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('collection', ctx.project.file("${ctx.observeRoot}/sql/${ctx.sqlPrimarySourceSet}/${schema}/procedures").toURI().toString())
                    param('schema', schema)
                    param('select-pattern', '*.xir')
                }

                ctx.project.tasks.register("sqlCallTreeIndex${schemaCap}", ctx.xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL call-tree index for ${schema}."
                    style "${observeStepRoot}/src/main/xsl/call-tree-indexer.xsl"
                    input "${observeStepRoot}/src/main/xml/call-tree.xml"
                    output "${ctx.sqlIndexRoot}/call-tree.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('input-uri', ctx.project.file("${ctx.observeRoot}/sql/${ctx.sqlPrimarySourceSet}/${schema}/procedures").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
                    param('schema-name', schema)
                }
            }
        }

        ctx.project.tasks.register("buildSqlIndicesForStitch") {
            group = 'lineage'
            description = 'Build SQL index artifacts required by call-app.xsl.'
            dependsOn("extractLineageObservations")
            if (ctx.cfg.sqlEnabled) {
                dependsOn(ctx.schemaNames.collect { "sqlTableIndex${it.capitalize()}" })
                dependsOn(ctx.schemaNames.collect { "sqlProcedureIndex${it.capitalize()}" })
                dependsOn(ctx.schemaNames.collect { "sqlCallTreeIndex${it.capitalize()}" })
            }
        }

        ctx.project.tasks.register("mergeDirectFlows", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: mergeDirectFlows'
            dependsOn("validateDirectFlows")
            style "${stepRoot}/src/main/xsl/merge-direct-flows.xsl"
            input "${ctx.validateDirectFlowRoot}/direct-flows.xml"
            output "${ctx.mergeRoot}/direct-flows.merged.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
        }
    }
}
