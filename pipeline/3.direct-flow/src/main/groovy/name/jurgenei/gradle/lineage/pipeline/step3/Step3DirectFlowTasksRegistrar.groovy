package org.flowdigger.gradle.lineage.pipeline.step3

class Step3DirectFlowTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step3-direct-flow')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/3.direct-flow"
        def sqlDirectFlowTasks = []
        ctx.sqlSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def taskName = "deriveSqlDirectFlows${ctx.toTaskSuffix(name)}"
            sqlDirectFlowTasks << taskName
            ctx.project.tasks.register(taskName, ctx.xsltTaskClass) {
                group = 'lineage'
                description = "Phase 3.direct-flow SQL direct flow derivation for ${name}."
                dependsOn("observeSql${ctx.toTaskSuffix(name)}")
                style "${stepRoot}/src/main/xsl/direct-flow-sql.xsl"
                source(ctx.project.fileTree("${ctx.observeRoot}/sql/${name}") {
                    include '**/*.xir'
                })
                outputDir.set(ctx.project.file("${ctx.directFlowRoot}/sql/${name}"))
                outputExtension.set('.xml')
                outputFormat.set('beautified')
            }
        }

        def javaDirectFlowTasks = []
        ctx.javaSourceSetNames.each { key ->
            javaDirectFlowTasks << "deriveJavaDirectFlows${ctx.javaTaskSuffixes[key]}"
        }

        ctx.javaSourceSetNames.each { key ->
            def suffix = ctx.javaTaskSuffixes[key]
            ctx.project.tasks.register("mergeJavaFlows${suffix}", ctx.xsltTaskClass) {
                group = 'lineage'
                description = "Merge Java flow graphs for ${key}."
                dependsOn("observeJava${suffix}")
                style "${stepRoot}/src/main/xsl/javaflow-merge.xsl"
                input "${stepRoot}/src/main/xml/seed.xml"
                output "${ctx.directFlowRoot}/java/${key}/${key}.seed.xml"
                outputFormat.set('beautified')
                param('input-uri', ctx.project.file("${ctx.observeRoot}/java/${key}").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
            }

            ctx.project.tasks.register("deriveJavaDirectFlows${suffix}", ctx.xsltTaskClass) {
                group = 'lineage'
                description = "Phase 3.direct-flow Java direct flow derivation for ${key}."
                dependsOn("mergeJavaFlows${suffix}")
                style "${stepRoot}/src/main/xsl/direct-flow-java-merged.xsl"
                input "${ctx.directFlowRoot}/java/${key}/${key}.seed.xml"
                output "${ctx.directFlowRoot}/java/${key}/direct-flow.${key}.xml"
            }
        }

        ctx.project.tasks.register("deriveDirectFlows") {
            group = 'lineage'
            description = 'Lifecycle stage: deriveDirectFlows'
            dependsOn("extractLineageObservations")
            dependsOn(sqlDirectFlowTasks)
            dependsOn(javaDirectFlowTasks)
        }
    }
}
