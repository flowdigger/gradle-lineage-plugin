package org.flowdigger.gradle.lineage

import org.gradle.api.Project

class LineageGlobalTasks {
    static void register(Project project, LineagePipelineExtension ext) {
        project.tasks.named("clean") { cleanTask ->
            cleanTask.description = "Clean project build outputs and lineage stages 2..9 while preserving 1.parse artifacts."
            cleanTask.outputs.upToDateWhen { false }
            cleanTask.doLast {
                def lineageBuildRoot = (project.findProperty('lineageBuildRoot') ?: ext.lineageBuildRoot).toString()
                def lineageRoot = project.file(lineageBuildRoot)
                if (!lineageRoot.exists()) {
                    project.logger.lifecycle("lineageBuildRoot does not exist, skipping lineage stage cleanup: ${lineageRoot}")
                    return
                }

                def removableStages = lineageRoot.listFiles()?.findAll { it.isDirectory() && it.name != '1.parse' } ?: []
                if (removableStages.isEmpty()) {
                    project.logger.lifecycle("No lineage stages to clean under ${lineageRoot} (1.parse preserved).")
                    return
                }

                project.delete(removableStages)
                project.logger.lifecycle("Removed lineage stages: ${removableStages*.name.sort().join(', ')} (preserved: 1.parse)")
            }
        }

        project.tasks.register("cleanAllLineage") {
            group = "build"
            description = "Remove complete lineage build root including 1.parse."
            doLast {
                def lineageBuildRoot = (project.findProperty('lineageBuildRoot') ?: ext.lineageBuildRoot).toString()
                project.delete(project.file(lineageBuildRoot))
            }
        }

        project.tasks.named("build") {
            dependsOn("publishLineage")
        }
    }
}
