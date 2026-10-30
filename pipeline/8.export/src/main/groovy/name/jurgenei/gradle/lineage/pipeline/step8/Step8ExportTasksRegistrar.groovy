package name.jurgenei.gradle.lineage.pipeline.step8

import org.gradle.api.GradleException

class Step8ExportTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step8-export')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/8.export"
        ctx.project.tasks.register("carryAppXirToExport") {
            group = 'lineage'
            description = 'Carry per-processor app lineage artifacts from validation phase.'
            dependsOn("carryAppXirToValidation")
            doLast {
                ctx.project.copy {
                    from("${ctx.validateRoot}/lineage/app/xir")
                    into("${ctx.exportRoot}/lineage/app/xir")
                    include("**/*.xir")
                }
                ctx.project.copy {
                    from("${ctx.validateRoot}/lineage/app/xir")
                    into("${ctx.exportRoot}/lineage/app/txt")
                    include("**/*.xir")
                    rename '(.*)\\.xir', '$1.xir.txt'
                }
            }
        }

        ctx.project.tasks.register("exportGraphML", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: exportGraphML'
            dependsOn("validateLineage")
            style "${stepRoot}/src/main/xsl/stitched-to-graphml.xsl"
            input "${ctx.stitchRoot}/stitched-lineage.xml"
            output "${ctx.exportRoot}/graphml/lineage.graphml"
            outputExtension.set('.graphml')
            outputFormat.set('beautified')
        }

        ctx.project.tasks.register("exportRDF", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: exportRDF'
            dependsOn("validateLineage")
            style "${stepRoot}/src/main/xsl/stitched-to-rdf.xsl"
            input "${ctx.stitchRoot}/stitched-lineage.xml"
            output "${ctx.exportRoot}/rdf/lineage.rdf"
            outputExtension.set('.rdf')
            outputFormat.set('beautified')
        }

        ctx.project.tasks.register("exportJsonForGraph", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Export JSON projection for graph layout consumer.'
            dependsOn("validateLineage")
            style "${stepRoot}/src/main/xsl/stitched-to-json.xsl"
            input "${ctx.stitchRoot}/stitched-lineage.xml"
            output "${ctx.exportRoot}/json/lineage.json"
        }

        ctx.project.tasks.register('addLayout', ctx.pythonRunnerTaskClass) { t ->
            group = 'lineage'
            description = 'Add graph layout enrichment to exported lineage JSON files.'
            dependsOn("exportJsonForGraph")
            t.script = ctx.project.file("${stepRoot}/src/python/main.py")
            t.requirements = ctx.project.file("${stepRoot}/src/python/requirements.txt")
            t.workDir = ctx.project.file("${ctx.exportRoot}/graph")
            t.args = ["${ctx.exportRoot}/json", "${ctx.exportRoot}/graph"] as String[]
        }

        def appXirSourceDir = "${ctx.exportRoot}/lineage/app/xir"
        ctx.project.tasks.register("exportAppGraphML", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Export per-processor GraphML projections from app lineage artifacts.'
            dependsOn("carryAppXirToExport")
            style "${stepRoot}/src/main/xsl/app-to-graphml.xsl"
            source(ctx.project.fileTree(appXirSourceDir) {
                include '**/*.xir'
            })
            outputDir.set(ctx.project.file("${ctx.exportRoot}/app/graphml"))
            outputExtension.set('.graphml')
            outputFormat.set('beautified')
        }

        ctx.project.tasks.register("exportAppRDF", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Export per-processor RDF projections from app lineage artifacts.'
            dependsOn("carryAppXirToExport")
            style "${stepRoot}/src/main/xsl/app-to-rdf.xsl"
            source(ctx.project.fileTree(appXirSourceDir) {
                include '**/*.xir'
            })
            outputDir.set(ctx.project.file("${ctx.exportRoot}/app/rdf"))
            outputExtension.set('.rdf')
            outputFormat.set('beautified')
        }

        ctx.project.tasks.register('exportAppJson', ctx.pythonRunnerTaskClass) { t ->
            group = 'lineage'
            description = 'Export per-processor JSON projections from per-processor GraphML outputs.'
            dependsOn("exportAppGraphML")
            t.script = ctx.project.file("${stepRoot}/src/python/app_graphml_to_json.py")
            t.requirements = ctx.project.file("${stepRoot}/src/python/requirements.txt")
            t.workDir = ctx.project.file("${ctx.exportRoot}/app/json")
            t.args = ["${ctx.exportRoot}/app/graphml", "${ctx.exportRoot}/app/json"] as String[]
        }

        ctx.project.tasks.register("exportLineageArtifacts") {
            group = 'lineage'
            description = 'Lifecycle stage: export lineages and projections.'
            dependsOn("exportGraphML", "exportRDF", "exportJsonForGraph", "addLayout")
            dependsOn("carryAppXirToExport", "exportAppGraphML", "exportAppRDF", "exportAppJson")
        }

        ctx.project.tasks.register("verifyPerProcessorExports") {
            group = 'lineage'
            description = 'Fail when per-processor export artifacts are missing.'
            dependsOn("exportLineageArtifacts")
            doLast {
                def graphmlFiles = ctx.project.fileTree("${ctx.exportRoot}/app/graphml") { include '**/*.graphml' }.files
                def rdfFiles = ctx.project.fileTree("${ctx.exportRoot}/app/rdf") { include '**/*.rdf' }.files
                def jsonFiles = ctx.project.fileTree("${ctx.exportRoot}/app/json") { include '**/*.json' }.files
                if (graphmlFiles.isEmpty() || rdfFiles.isEmpty() || jsonFiles.isEmpty()) {
                    throw new GradleException("Missing per-processor exports under ${ctx.exportRoot}/app/{graphml,json,rdf}")
                }
            }
        }
    }
}
