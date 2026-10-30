package name.jurgenei.gradle.lineage.pipeline.step9

class Step9PublishTasksRegistrar {
    static void register(def ctx) {
        ctx.project.tasks.register("publishLineage") {
            group = 'lineage'
            description = 'Lifecycle stage: publishLineage'
            dependsOn("exportLineageArtifacts")
            dependsOn("verifyPerProcessorExports")
            doLast {
                ctx.project.copy {
                    from(ctx.exportRoot)
                    into("${ctx.publishRoot}/artifacts")
                }
            }
        }
    }
}
