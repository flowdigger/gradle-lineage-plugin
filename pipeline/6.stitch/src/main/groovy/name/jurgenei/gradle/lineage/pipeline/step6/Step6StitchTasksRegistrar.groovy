package name.jurgenei.gradle.lineage.pipeline.step6

import org.gradle.api.GradleException

class Step6StitchTasksRegistrar {
    static void register(def ctx) {
        def stepRoot = ctx.project.findProject(':pipeline:step6-stitch')?.projectDir?.absolutePath ?: "${ctx.pipelineRoot}/6.stitch"
        def architectureModelFile = ctx.cfg.architectureModelFile.toString()
        def architectureProcessedFile = ctx.cfg.architectureProcessedFile.toString()
        ctx.project.tasks.register("stageStitchInputs") {
            group = 'lineage'
            description = 'Stage configuration and observed lineage assets for call-app stitching.'
            dependsOn("extractLineageObservations", "deriveDirectFlows", "buildSqlIndicesForStitch")
            doLast {
                ctx.project.copy {
                    from("${ctx.observeRoot}/configuration")
                    into("${ctx.stitchRoot}/configuration")
                }
                if (ctx.cfg.sqlEnabled) {
                    ctx.project.copy {
                        from(ctx.sqlIndexRoot)
                        into("${ctx.stitchRoot}/lineage")
                    }
                }
            }
        }

        ctx.project.tasks.register("verifyCallAppSqlInputs") {
            group = 'lineage'
            description = 'Fail fast when required SQL and Java resources for call-app are missing.'
            dependsOn("stageStitchInputs")
            doLast {
                if (!ctx.cfg.sqlEnabled) {
                    logger.lifecycle("Skipping SQL index verification for call-app because SQL parser selector is disabled.")
                    return
                }
                ['call-tree', 'procedure', 'table-index'].each { prefix ->
                    def matches = ctx.project.fileTree("${ctx.stitchRoot}/lineage") {
                        include "${prefix}.*.xir"
                        include "${prefix}.*.xml"
                    }.files
                    if (matches.isEmpty()) {
                        throw new GradleException("Missing SQL index resources for call-app: ${prefix}.*.{xir,xml} under ${ctx.stitchRoot}/lineage")
                    }
                }

                if (ctx.cfg.javaEnabled) {
                    (ctx.cfg.javaSourceSetNames ?: []).each { domain ->
                        def javaDirectFlowFile = ctx.project.file("${ctx.directFlowRoot}/java/${domain}/direct-flow.${domain}.xml")
                        if (!javaDirectFlowFile.exists()) {
                            throw new GradleException("Missing Java direct-flow resource for call-app: ${javaDirectFlowFile}. Run deriveDirectFlows before stitch generation.")
                        }
                    }
                }
            }
        }

        ctx.project.tasks.register('generateApps', ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Generate stitched application artifacts using architecture + configuration glue.'
            dependsOn("verifyCallAppSqlInputs")
            doFirst {
                ctx.project.delete(architectureProcessedFile)
            }
            input architectureModelFile
            style "${stepRoot}/src/main/xsl/call-app.xsl"
            output architectureProcessedFile
            param 'work-uri', ctx.project.file(ctx.stitchRoot).toURI().toString()
        }

        ctx.project.tasks.register('postProcessApps', ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Convert generated stitched application XML artifacts to XIR.'
            dependsOn("generateApps")
            def srcDir = ctx.project.file("${ctx.stitchRoot}/lineage/app/xml")
            def destDir = ctx.project.file("${ctx.stitchRoot}/lineage/app/xir")
            doFirst {
                ctx.project.delete(destDir)
            }
            style "${stepRoot}/src/main/xsl/identity.xsl"
            source(ctx.project.fileTree(srcDir) {
                include '**/*.xml'
            })
            outputExtension.set('.xir')
            outputFormat.set('beautified')
            outputDir.set(destDir)
        }

        ctx.project.tasks.register("verifyVreJavaLineageCoverage") {
            group = 'lineage'
            description = 'Fail fast when VRE Java lineage coverage for DSA is missing in batch app outputs.'
            dependsOn("postProcessApps")
            onlyIf { !ctx.cfg.skipValidations && ctx.cfg.javaEnabled }
            doLast {
                def failOnZeroOperationalFlow = ctx.parseBool(ctx.project.findProperty('lineageFailOnZeroOperationalFlow')
                        ?: ctx.project.providers.environmentVariable('LINEAGE_FAIL_ON_ZERO_OPERATIONAL_FLOW').orNull
                        ?: 'false')
                ['buss.vre.batch.xml', 'cons.vre.batch.xml'].each { appFileName ->
                    def appFile = ctx.project.file("${ctx.stitchRoot}/lineage/app/xml/${appFileName}")
                    if (!appFile.exists()) {
                        throw new GradleException("Missing stitched app artifact for coverage validation: ${appFile}")
                    }

                    def factory = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                    factory.setNamespaceAware(false)
                    def appDoc = factory.newDocumentBuilder().parse(appFile)
                    def xpath = javax.xml.xpath.XPathFactory.newInstance().newXPath()
                    def dsaJavaLineageCount = xpath.evaluate("count(/applicationcomponent/database[@name='dsa']/java-lineage)", appDoc) as Double
                    if (dsaJavaLineageCount < 1d) {
                        throw new GradleException("Missing DSA java-lineage section in ${appFileName}. Add <database name=\"dsa\"><java-lineage .../></database> for VRE coverage.")
                    }

                    def operationalRoleCount = xpath.evaluate("count(/applicationcomponent/database[@name='dsa']/java-lineage/role[@name='operational' and @schema='dsa'])", appDoc) as Double
                    if (operationalRoleCount < 1d) {
                        throw new GradleException("Missing DSA operational role in ${appFileName} java-lineage.")
                    }

                    def totalOperationalFlowCount = xpath.evaluate("sum(/applicationcomponent/database/java-lineage/role[@name='operational']/@flow-count)", appDoc) as Double
                    if (totalOperationalFlowCount.isNaN() || totalOperationalFlowCount <= 0) {
                        def msg = "No operational java-lineage flows found in ${appFileName}. Check class-prefix selectors and Java direct-flow inputs."
                        if (failOnZeroOperationalFlow) {
                            throw new GradleException(msg)
                        }
                        logger.lifecycle("WARN: ${msg} Continuing because strict zero-flow enforcement is disabled. Enable with -PlineageFailOnZeroOperationalFlow=true or LINEAGE_FAIL_ON_ZERO_OPERATIONAL_FLOW=true.")
                    }
                }
            }
        }

        ctx.project.tasks.register("stitchLineage", ctx.xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: stitchLineage'
            dependsOn("mergeDirectFlows")
            dependsOn("verifyVreJavaLineageCoverage")
            style "${stepRoot}/src/main/xsl/stitch-lineage.xsl"
            input "${ctx.mergeRoot}/direct-flows.merged.xml"
            output "${ctx.stitchRoot}/stitched-lineage.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
            param('table-index-uri', ctx.project.file("${ctx.stitchRoot}/lineage").toURI().toString() + '?select=table-index.*.xir;on-error=ignore')
            doFirst {
                ctx.project.delete(ctx.project.file("${ctx.stitchRoot}/stitched-lineage.xml"))
            }
            outputs.upToDateWhen { !ctx.cleanRequested }
        }
    }
}
