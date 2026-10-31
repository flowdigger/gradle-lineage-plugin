package org.flowdigger.gradle.lineage.pipeline.step1

import org.gradle.api.GradleException

class Step1ParseTasksRegistrar {
    static void register(def ctx) {
        def parseTasks = []
        def configurePlsqlTask = { Object t, Map<String, Object> sourceSet ->
            t.compression = true
            t.sourceDirectory.set(ctx.project.file(sourceSet.sourceDirectoryAbsolute.toString()))
            t.destinationDirectory.set(ctx.project.file("${ctx.parseRoot}/sql/${sourceSet.name}/ast"))
            t.includes.set(sourceSet.includes as List<String>)
            t.executionModel.set('VIRTUAL_THREADS')
            t.parallelism.set(3)
            t.aggressiveGc.set(true)
            t.gcEveryFiles.set(20)
            t.gcHeapThresholdPercent.set(80)
            t.targetExtension.set('.xir')
            t.continueOnError.set(true)
            t.failOnError.set(false)
            t.failOnTransformationError.set(false)
            t.force.set(false)
            t.suppressStackTrace.set(true)
        }
        ctx.cfg.sourceSets.each { sourceSet ->
            def sourceSetName = sourceSet.name.toString()
            def taskSuffix = ctx.toTaskSuffix(sourceSetName)
            if (sourceSet.parserKind == 'plsql') {
                def taskName = "parsePlsqlSources${taskSuffix}"
                parseTasks << taskName
                ctx.project.tasks.register(taskName, ctx.xmlAstPlsqlTaskClass) { t ->
                    group = 'lineage'
                    description = "Phase 1.parse PLSQL AST extraction for ${sourceSetName}."
                    dependsOn("syncLineageRepos")
                    configurePlsqlTask(t, sourceSet as Map<String, Object>)
                }
                return
            }

            if (sourceSet.parserKind == 'java') {
                def taskName = "parseJavaSources${taskSuffix}"
                parseTasks << taskName
                ctx.project.tasks.register(taskName, ctx.xmlAstJavaTaskClass) { t ->
                    group = 'lineage'
                    description = "Phase 1.parse Java AST extraction for ${sourceSetName}."
                    dependsOn("syncLineageRepos")
                    t.sourceDirectory.set(ctx.project.file(sourceSet.sourceDirectoryAbsolute.toString()))
                    t.destinationDirectory.set(ctx.project.file("${ctx.parseRoot}/java/${sourceSetName}/ast"))
                    t.targetExtension.set(".xml")
                    t.includes.set(sourceSet.includes as List<String>)
                    t.outputFormat.set('beautified')
                    t.continueOnError.set(true)
                }
                return
            }

            throw new GradleException("Parser plugin '${sourceSet.parserPlugin}' for sourceSet '${sourceSetName}' not wired in parse phase. Supported now: PLSQL and Java.")
        }

        ctx.project.tasks.register("parseLineageSources") {
            group = 'lineage'
            description = 'Lifecycle stage: parseLineageSources'
            dependsOn("syncLineageRepos")
            dependsOn(parseTasks)
        }
    }
}
