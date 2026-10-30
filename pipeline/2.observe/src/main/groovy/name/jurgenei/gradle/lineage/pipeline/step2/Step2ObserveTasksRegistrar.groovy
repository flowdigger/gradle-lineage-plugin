package name.jurgenei.gradle.lineage.pipeline.step2

class Step2ObserveTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step2-observe')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/2.observe"
        def sqlObserveTasks = []
        ctx.sqlSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def taskName = "observeSql${ctx.toTaskSuffix(name)}"
            sqlObserveTasks << taskName
            ctx.project.tasks.register(taskName, ctx.xsltTaskClass) {
                group = 'lineage'
                description = "Phase 2.observe SQL semantic extraction for ${name}."
                dependsOn("parsePlsqlSources${ctx.toTaskSuffix(name)}")
                style "${stepRoot}/src/main/xsl/extract.xsl"
                source(ctx.project.fileTree("${ctx.parseRoot}/sql/${name}/ast") {
                    include '**/*.xir'
                })
                outputExtension.set('.xir')
                outputFormat.set('beautified')
                outputDir.set(ctx.project.file("${ctx.observeRoot}/sql/${name}"))
            }
        }

        def javaObserveTasks = []
        ctx.javaSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def suffix = ctx.toTaskSuffix(name)
            def taskName = "observeJava${suffix}"
            javaObserveTasks << taskName
            ctx.project.tasks.register(taskName, ctx.xsltTaskClass) {
                group = 'lineage'
                description = "Phase 2.observe Java semantic extraction for ${name}."
                dependsOn("parseJavaSources${suffix}")
                style "${stepRoot}/src/main/xsl/javaflow-extract.xsl"
                source(ctx.project.fileTree("${ctx.parseRoot}/java/${name}/ast") {
                    include '**/*.xml'
                })
                outputExtension.set('.xir')
                outputFormat.set('beautified')
                outputDir.set(ctx.project.file("${ctx.observeRoot}/java/${name}"))
            }
        }

        ctx.project.tasks.register('generateConfiguration', ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Generate stitched lineage configuration observations.'
            outputDir.set(ctx.project.file("${ctx.observeRoot}/configuration"))
            style "${stepRoot}/src/main/xsl/configuration-prep.xsl"
            source(ctx.project.fileTree("${ctx.cfg.sourceRoot}/configuration") {
                include '**/*.xml'
            })
        }

        ctx.project.tasks.named('ooxmlToCanonical') {
            group = 'lineage'
            description = 'Observe OOXML documents under docs/active.'
            source(ctx.project.fileTree("${ctx.cfg.sourceRoot}/docs/active") {
                include '**/*.docx', '**/*.pptx', '**/*.xlsx'
                exclude '**/~$*'
            })
            outputDirectory.set(ctx.project.file("${ctx.observeRoot}/ooxml/active"))
            targetExtension.set('.xml')
            legacyXmlOutput.set(true)
        }

        ctx.project.tasks.register('fdToCanonical', ctx.ooxmlTaskClass) {
            group = 'lineage'
            description = 'Observe functional-design OOXML documents under docs/fd.'
            source(ctx.project.fileTree("${ctx.cfg.sourceRoot}/docs/fd") {
                include '**/*.docx', '**/*.pptx', '**/*.xlsx'
                exclude '**/~$*'
            })
            outputDirectory.set(ctx.project.file("${ctx.observeRoot}/ooxml/fd"))
            targetExtension.set('.xir')
            legacyXmlOutput.set(true)
        }

        ctx.project.tasks.register("ooxmlTablesToXir", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Translate canonical OOXML tables to XIR objects.'
            dependsOn('ooxmlToCanonical')
            style("${stepRoot}/src/main/xsl/table2objects.xsl")
            source(ctx.project.fileTree("${ctx.observeRoot}/ooxml/active") {
                include("**/*.xml")
            })
            outputDir.set(ctx.project.file("${ctx.observeRoot}/ooxml/fd"))
            outputExtension.set('.xir')
            outputFormat.set('beautified')
        }

        ctx.project.tasks.register("extractLineageObservations") {
            group = 'lineage'
            description = 'Lifecycle stage: extractLineageObservations'
            dependsOn("parseLineageSources")
            dependsOn(sqlObserveTasks)
            dependsOn(javaObserveTasks)
            dependsOn("generateConfiguration")
            dependsOn("ooxmlToCanonical", "fdToCanonical", "ooxmlTablesToXir")
        }
    }
}
