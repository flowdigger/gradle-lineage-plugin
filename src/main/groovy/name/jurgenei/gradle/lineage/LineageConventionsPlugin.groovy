package name.jurgenei.gradle.lineage

import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import java.io.BufferedInputStream
import java.io.FileInputStream


class LineageConventionsPlugin implements Plugin<Project> {
    private static final String ANTLR_PLUGIN_ID = 'name.jurgenei.gradle.antlr'

    @Override
    void apply(Project project) {
        if (project != project.rootProject) {
            throw new GradleException("name.jurgenei.gradle.lineage must be applied to root project only.")
        }

        def ext = project.extensions.create('lineagePipeline', LineagePipelineExtension)
        ext.sourceRoot = project.rootProject.projectDir.parentFile.absolutePath
        ext.lineageBuildRoot = (
                project.findProperty('buildRoot')
                        ?: project.findProperty('lineageBuildRoot')
                        ?: project.providers.environmentVariable('LINEAGE_BUILD_ROOT').orNull
                        ?: project.layout.buildDirectory.dir('lineage-uniform').get().asFile.absolutePath
        ).toString()
        project.rootProject.ext.resolveLineageConfig = { ->
            resolveLineageConfig(project, ext)
        }

        project.afterEvaluate {
            def cfg = resolveLineageConfig(project, ext)
            registerRepoSyncTasks(project, cfg)
            registerPipelineTasks(project, cfg, ext)
            project.rootProject.ext.lineage = cfg
        }
    }

    private static void registerPipelineTasks(Project project, Map<String, Object> cfg, LineagePipelineExtension ext) {
        project.pluginManager.apply('name.jurgenei.gradle.xml')
        project.pluginManager.apply('name.jurgenei.gradle.ooxml')
        project.pluginManager.apply('name.jurgenei.gradle.python')
        if (cfg.sqlEnabled) {
            project.pluginManager.apply('name.jurgenei.gradle.antlr.plsql')
        }
        if (cfg.javaEnabled) {
            project.pluginManager.apply('name.jurgenei.gradle.antlr.java')
        }

        def xmlAstPlsqlTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.antlr.XmlAstPlsqlGradleTask')
        def xmlAstJavaTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.antlr.XmlAstJavaGradleTask')
        def xsltTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.xml.XsltTask')
        def schematronTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.xml.SchematronTask')
        def ooxmlTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.ooxml.OoXmlToCanonicalTask')
        def pythonRunnerTaskClass = LineageConventionsPlugin.classLoader.loadClass('name.jurgenei.gradle.python.PythonRunnerTask')
        def copyTaskClass = LineageConventionsPlugin.classLoader.loadClass('org.gradle.api.tasks.Copy')

        def toTaskSuffix = { String key ->
            key.split(/[^A-Za-z0-9]+/)
                    .findAll { !it.isBlank() }
                    .collect { it.capitalize() }
                    .join('')
        }
        def parseBool = { Object v ->
            def s = (v ?: '').toString().trim().toLowerCase()
            s in ['1', 'true', 'yes', 'y', 'on']
        }
        def cleanRequested = project.gradle.startParameter.taskNames.any { taskName ->
            taskName == 'clean' || taskName.endsWith(':clean') || taskName == 'cleanAllLineage' || taskName.endsWith(':cleanAllLineage')
        }
        def includedPluginBuild = project.gradle.includedBuilds.find { it.name == 'gradle-lineage-plugin' }
        def pipelineRoot = (project.findProperty('lineagePluginPipelineRoot')
                ?: project.providers.environmentVariable('LINEAGE_PLUGIN_PIPELINE_ROOT').orNull
                ?: (includedPluginBuild != null ? new File(includedPluginBuild.projectDir, 'pipeline').absolutePath : "${project.rootProject.projectDir}/build-logic/pipeline"))
                .toString()
        def toCollectionUri = { String dirPath, String selectPattern ->
            def dirUri = project.file(dirPath).toURI().toString()
            def normalized = dirUri.endsWith('/') ? dirUri : "${dirUri}/"
            "${normalized}?select=${selectPattern};recurse=yes;on-error=ignore"
        }

        def buildRoot = cfg.buildRoot.toString()
        def parseRoot = "${buildRoot}/1.parse"
        def observeRoot = "${buildRoot}/2.observe"
        def directFlowRoot = "${buildRoot}/3.direct-flow"
        def validateDirectFlowRoot = "${buildRoot}/4.validate-direct-flow"
        def mergeRoot = "${buildRoot}/5.merge"
        def stitchRoot = "${buildRoot}/6.stitch"
        def validateRoot = "${buildRoot}/7.validate-lineage"
        def exportRoot = "${buildRoot}/8.export"
        def publishRoot = "${buildRoot}/9.publish"
        def sqlIndexRoot = "${mergeRoot}/sql-index"

        def sqlSourceSets = (cfg.sqlSourceSets ?: []) as List<Map<String, Object>>
        def javaSourceSets = (cfg.javaSourceSets ?: []) as List<Map<String, Object>>
        def javaSourceSetNames = (cfg.javaSourceSetNames ?: []).collect { it.toString() }.sort()
        def javaTaskSuffixes = javaSourceSetNames.collectEntries { [(it): toTaskSuffix(it)] }
        def schemaNames = (cfg.schemaNames ?: []).collect { it.toString() }
        def sqlPrimarySourceSet = sqlSourceSets ? sqlSourceSets[0].name.toString() : null

        def parseTasks = []
        def configurePlsqlTask = { Object t, Map<String, Object> sourceSet ->
            t.compression = true
            t.sourceDirectory.set(project.file(sourceSet.sourceDirectoryAbsolute.toString()))
            t.destinationDirectory.set(project.file("${parseRoot}/sql/${sourceSet.name}/ast"))
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
        cfg.sourceSets.each { sourceSet ->
            def sourceSetName = sourceSet.name.toString()
            def taskSuffix = toTaskSuffix(sourceSetName)
            if (sourceSet.parserKind == 'plsql') {
                def taskName = "parsePlsqlSources${taskSuffix}"
                parseTasks << taskName
                project.tasks.register(taskName, xmlAstPlsqlTaskClass) { t ->
                    group = 'lineage'
                    description = "Phase 1.parse PLSQL AST extraction for ${sourceSetName}."
                    configurePlsqlTask(t, sourceSet as Map<String, Object>)
                }
                return
            }

            if (sourceSet.parserKind == 'java') {
                def taskName = "parseJavaSources${taskSuffix}"
                parseTasks << taskName
                project.tasks.register(taskName, xmlAstJavaTaskClass) { t ->
                    group = 'lineage'
                    description = "Phase 1.parse Java AST extraction for ${sourceSetName}."
                    t.sourceDirectory.set(project.file(sourceSet.sourceDirectoryAbsolute.toString()))
                    t.destinationDirectory.set(project.file("${parseRoot}/java/${sourceSetName}/ast"))
                    t.targetExtension.set(".xml")
                    t.includes.set(sourceSet.includes as List<String>)
                    t.outputFormat.set('beautified')
                    t.continueOnError.set(true)
                }
                return
            }

            throw new GradleException("Parser plugin '${sourceSet.parserPlugin}' for sourceSet '${sourceSetName}' not wired in parse phase. Supported now: PLSQL and Java.")
        }

        project.tasks.register("parseLineageSources") {
            group = 'lineage'
            description = 'Lifecycle stage: parseLineageSources'
            dependsOn("syncLineageRepos")
            dependsOn(parseTasks)
        }

        def sqlObserveTasks = []
        sqlSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def taskName = "observeSql${toTaskSuffix(name)}"
            sqlObserveTasks << taskName
            project.tasks.register(taskName, xsltTaskClass) {
                group = 'lineage'
                description = "Phase 2.observe SQL semantic extraction for ${name}."
                dependsOn("parsePlsqlSources${toTaskSuffix(name)}")
                style "${pipelineRoot}/2.observe/src/main/xsl/extract.xsl"
                source(project.fileTree("${parseRoot}/sql/${name}/ast") {
                    include '**/*.xir'
                })
                outputExtension.set('.xir')
                outputFormat.set('beautified')
                outputDir.set(project.file("${observeRoot}/sql/${name}"))
            }
        }

        def javaObserveTasks = []
        javaSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def suffix = toTaskSuffix(name)
            def taskName = "observeJava${suffix}"
            javaObserveTasks << taskName
            project.tasks.register(taskName, xsltTaskClass) {
                group = 'lineage'
                description = "Phase 2.observe Java semantic extraction for ${name}."
                dependsOn("parseJavaSources${suffix}")
                style "${pipelineRoot}/2.observe/src/main/xsl/javaflow-extract.xsl"
                source(project.fileTree("${parseRoot}/java/${name}/ast") {
                    include '**/*.xml'
                })
                outputExtension.set('.xir')
                outputFormat.set('beautified')
                outputDir.set(project.file("${observeRoot}/java/${name}"))
            }
        }

        project.tasks.register('generateConfiguration', xsltTaskClass) {
            group = 'lineage'
            description = 'Generate stitched lineage configuration observations.'
            outputDir.set(project.file("${observeRoot}/configuration"))
            style "${pipelineRoot}/2.observe/src/main/xsl/configuration-prep.xsl"
            source(project.fileTree("${cfg.sourceRoot}/configuration") {
                include '**/*.xml'
            })
        }

        project.tasks.named('ooxmlToCanonical') {
            group = 'lineage'
            description = 'Observe OOXML documents under docs/active.'
            source(project.fileTree("${cfg.sourceRoot}/docs/active") {
                include '**/*.docx', '**/*.pptx', '**/*.xlsx'
                exclude '**/~$*'
            })
            outputDirectory.set(project.file("${observeRoot}/ooxml/active"))
            targetExtension.set('.xml')
            legacyXmlOutput.set(true)
        }

        project.tasks.register('fdToCanonical', ooxmlTaskClass) {
            group = 'lineage'
            description = 'Observe functional-design OOXML documents under docs/fd.'
            source(project.fileTree("${cfg.sourceRoot}/docs/fd") {
                include '**/*.docx', '**/*.pptx', '**/*.xlsx'
                exclude '**/~$*'
            })
            outputDirectory.set(project.file("${observeRoot}/ooxml/fd"))
            targetExtension.set('.xir')
            legacyXmlOutput.set(true)
        }

        project.tasks.register("ooxmlTablesToXir", xsltTaskClass) {
            group = 'lineage'
            description = 'Translate canonical OOXML tables to XIR objects.'
            dependsOn('ooxmlToCanonical')
            style("${pipelineRoot}/2.observe/src/main/xsl/table2objects.xsl")
            source(project.fileTree("${observeRoot}/ooxml/active") {
                include("**/*.xml")
            })
            outputDir.set(project.file("${observeRoot}/ooxml/fd"))
            outputExtension.set('.xir')
            outputFormat.set('beautified')
        }

        project.tasks.register("extractLineageObservations") {
            group = 'lineage'
            description = 'Lifecycle stage: extractLineageObservations'
            dependsOn("parseLineageSources")
            dependsOn(sqlObserveTasks)
            dependsOn(javaObserveTasks)
            dependsOn("generateConfiguration")
            dependsOn("ooxmlToCanonical", "fdToCanonical", "ooxmlTablesToXir")
        }

        def sqlDirectFlowTasks = []
        sqlSourceSets.each { sourceSet ->
            def name = sourceSet.name.toString()
            def taskName = "deriveSqlDirectFlows${toTaskSuffix(name)}"
            sqlDirectFlowTasks << taskName
            project.tasks.register(taskName, xsltTaskClass) {
                group = 'lineage'
                description = "Phase 3.direct-flow SQL direct flow derivation for ${name}."
                dependsOn("observeSql${toTaskSuffix(name)}")
                style "${pipelineRoot}/3.direct-flow/src/main/xsl/direct-flow-sql.xsl"
                source(project.fileTree("${observeRoot}/sql/${name}") {
                    include '**/*.xir'
                })
                outputDir.set(project.file("${directFlowRoot}/sql/${name}"))
                outputExtension.set('.xml')
                outputFormat.set('beautified')
            }
        }

        def javaDirectFlowTasks = []
        javaSourceSetNames.each { key ->
            javaDirectFlowTasks << "deriveJavaDirectFlows${javaTaskSuffixes[key]}"
        }

        javaSourceSetNames.each { key ->
            def suffix = javaTaskSuffixes[key]
            project.tasks.register("mergeJavaFlows${suffix}", xsltTaskClass) {
                group = 'lineage'
                description = "Merge Java flow graphs for ${key}."
                dependsOn("observeJava${suffix}")
                style "${pipelineRoot}/3.direct-flow/src/main/xsl/javaflow-merge.xsl"
                input "${pipelineRoot}/3.direct-flow/src/main/xml/seed.xml"
                output "${directFlowRoot}/java/${key}/${key}.seed.xml"
                outputFormat.set('beautified')
                param('input-uri', project.file("${observeRoot}/java/${key}").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
            }

            project.tasks.register("deriveJavaDirectFlows${suffix}", xsltTaskClass) {
                group = 'lineage'
                description = "Phase 3.direct-flow Java direct flow derivation for ${key}."
                dependsOn("mergeJavaFlows${suffix}")
                style "${pipelineRoot}/3.direct-flow/src/main/xsl/direct-flow-java-merged.xsl"
                input "${directFlowRoot}/java/${key}/${key}.seed.xml"
                output "${directFlowRoot}/java/${key}/direct-flow.${key}.xml"
            }
        }

        project.tasks.register("deriveDirectFlows") {
            group = 'lineage'
            description = 'Lifecycle stage: deriveDirectFlows'
            dependsOn("extractLineageObservations")
            dependsOn(sqlDirectFlowTasks)
            dependsOn(javaDirectFlowTasks)
        }

        project.tasks.register("collectDirectFlows", xsltTaskClass) {
            group = 'lineage'
            description = 'Collect SQL and Java direct flow docs into one canonical document.'
            dependsOn("deriveDirectFlows")
            doFirst {
                project.file("${directFlowRoot}/java").mkdirs()
                project.file("${validateDirectFlowRoot}/direct-flows.xml").delete()
            }
            style "${pipelineRoot}/4.validate-direct-flow/src/main/xsl/collect-direct-flows.xsl"
            input "${pipelineRoot}/4.validate-direct-flow/src/main/xml/seed.xml"
            output "${validateDirectFlowRoot}/direct-flows.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
            param('sql-uri', toCollectionUri("${directFlowRoot}/sql", "*.xml"))
            param('java-uri', toCollectionUri("${directFlowRoot}/java", "direct-flow.*.xml"))
        }

        project.tasks.register("validateDirectFlows", schematronTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: validateDirectFlows'
            dependsOn("deriveDirectFlows", "collectDirectFlows")
            schema "${pipelineRoot}/4.validate-direct-flow/src/main/schematron/direct-flow-validation.sch"
            source project.file("${validateDirectFlowRoot}/direct-flows.xml")
            outputDir.set(project.file(validateDirectFlowRoot))
            failOnError.set(true)
            expandText.set(true)
            onlyIf { !cfg.skipValidations }
            doFirst {
                logger.lifecycle("Running direct-flow Schematron validation (skipLineageValidations=${cfg.skipValidations}).")
            }
        }

        if (cfg.sqlEnabled && sqlSourceSets.size() > 1) {
            throw new GradleException("Merge phase currently supports one SQL sourceSet. Found: ${sqlSourceSets*.name}")
        }
        if (cfg.sqlEnabled) {
            schemaNames.each { schema ->
                def schemaCap = schema.capitalize()
                project.tasks.register("sqlTableIndex${schemaCap}", xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL table index for ${schema}."
                    style "${pipelineRoot}/2.observe/src/main/xsl/table-procedure-indexer.xsl"
                    input "${pipelineRoot}/2.observe/src/main/xml/table-index.xml"
                    output "${sqlIndexRoot}/table-index.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('input-uri', project.file("${observeRoot}/sql/${sqlPrimarySourceSet}/${schema}").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
                    param('schema-name', schema)
                }

                project.tasks.register("sqlProcedureIndex${schemaCap}", xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL procedure index for ${schema}."
                    style "${pipelineRoot}/2.observe/src/main/xsl/index-procedures.xsl"
                    input "${pipelineRoot}/2.observe/src/main/xml/procedure-index.xml"
                    output "${sqlIndexRoot}/procedure.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('collection', project.file("${observeRoot}/sql/${sqlPrimarySourceSet}/${schema}/procedures").toURI().toString())
                    param('schema', schema)
                    param('select-pattern', '*.xir')
                }

                project.tasks.register("sqlCallTreeIndex${schemaCap}", xsltTaskClass) {
                    group = 'lineage'
                    description = "Build SQL call-tree index for ${schema}."
                    style "${pipelineRoot}/2.observe/src/main/xsl/call-tree-indexer.xsl"
                    input "${pipelineRoot}/2.observe/src/main/xml/call-tree.xml"
                    output "${sqlIndexRoot}/call-tree.${schema}.xir"
                    outputExtension.set('.xir')
                    outputFormat.set('beautified')
                    param('input-uri', project.file("${observeRoot}/sql/${sqlPrimarySourceSet}/${schema}/procedures").toURI().toString() + '?select=*.xir;recurse=yes;on-error=ignore')
                    param('schema-name', schema)
                }
            }
        }

        project.tasks.register("buildSqlIndicesForStitch") {
            group = 'lineage'
            description = 'Build SQL index artifacts required by call-app.xsl.'
            dependsOn("extractLineageObservations")
            if (cfg.sqlEnabled) {
                dependsOn(schemaNames.collect { "sqlTableIndex${it.capitalize()}" })
                dependsOn(schemaNames.collect { "sqlProcedureIndex${it.capitalize()}" })
                dependsOn(schemaNames.collect { "sqlCallTreeIndex${it.capitalize()}" })
            }
        }

        project.tasks.register("mergeDirectFlows", xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: mergeDirectFlows'
            dependsOn("validateDirectFlows")
            style "${pipelineRoot}/5.merge/src/main/xsl/merge-direct-flows.xsl"
            input "${validateDirectFlowRoot}/direct-flows.xml"
            output "${mergeRoot}/direct-flows.merged.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
        }

        def architectureModelFile = cfg.architectureModelFile.toString()
        def architectureProcessedFile = cfg.architectureProcessedFile.toString()
        project.tasks.register("stageStitchInputs") {
            group = 'lineage'
            description = 'Stage configuration and observed lineage assets for call-app stitching.'
            dependsOn("extractLineageObservations", "deriveDirectFlows", "buildSqlIndicesForStitch")
            doLast {
                project.copy {
                    from("${observeRoot}/configuration")
                    into("${stitchRoot}/configuration")
                }
                if (cfg.sqlEnabled) {
                    project.copy {
                        from(sqlIndexRoot)
                        into("${stitchRoot}/lineage")
                    }
                }
            }
        }

        project.tasks.register("verifyCallAppSqlInputs") {
            group = 'lineage'
            description = 'Fail fast when required SQL and Java resources for call-app are missing.'
            dependsOn("stageStitchInputs")
            doLast {
                if (!cfg.sqlEnabled) {
                    logger.lifecycle("Skipping SQL index verification for call-app because SQL parser selector is disabled.")
                    return
                }
                ['call-tree', 'procedure', 'table-index'].each { prefix ->
                    def matches = project.fileTree("${stitchRoot}/lineage") {
                        include "${prefix}.*.xir"
                        include "${prefix}.*.xml"
                    }.files
                    if (matches.isEmpty()) {
                        throw new GradleException("Missing SQL index resources for call-app: ${prefix}.*.{xir,xml} under ${stitchRoot}/lineage")
                    }
                }

                if (cfg.javaEnabled) {
                    (cfg.javaSourceSetNames ?: []).each { domain ->
                        def javaDirectFlowFile = project.file("${directFlowRoot}/java/${domain}/direct-flow.${domain}.xml")
                        if (!javaDirectFlowFile.exists()) {
                            throw new GradleException("Missing Java direct-flow resource for call-app: ${javaDirectFlowFile}. Run deriveDirectFlows before stitch generation.")
                        }
                    }
                }
            }
        }

        project.tasks.register('generateApps', xsltTaskClass) {
            group = 'lineage'
            description = 'Generate stitched application artifacts using architecture + configuration glue.'
            dependsOn("verifyCallAppSqlInputs")
            doFirst {
                project.delete(architectureProcessedFile)
            }
            input architectureModelFile
            style "${pipelineRoot}/6.stitch/src/main/xsl/call-app.xsl"
            output architectureProcessedFile
            param 'work-uri', project.file(stitchRoot).toURI().toString()
        }

        project.tasks.register('postProcessApps', xsltTaskClass) {
            group = 'lineage'
            description = 'Convert generated stitched application XML artifacts to XIR.'
            dependsOn("generateApps")
            def srcDir = project.file("${stitchRoot}/lineage/app/xml")
            def destDir = project.file("${stitchRoot}/lineage/app/xir")
            doFirst {
                project.delete(destDir)
            }
            style "${pipelineRoot}/6.stitch/src/main/xsl/identity.xsl"
            source(project.fileTree(srcDir) {
                include '**/*.xml'
            })
            outputExtension.set('.xir')
            outputFormat.set('beautified')
            outputDir.set(destDir)
        }

        project.tasks.register("verifyVreJavaLineageCoverage") {
            group = 'lineage'
            description = 'Fail fast when VRE Java lineage coverage for DSA is missing in batch app outputs.'
            dependsOn("postProcessApps")
            onlyIf { !cfg.skipValidations && cfg.javaEnabled }
            doLast {
                def failOnZeroOperationalFlow = parseBool(project.findProperty('lineageFailOnZeroOperationalFlow')
                        ?: project.providers.environmentVariable('LINEAGE_FAIL_ON_ZERO_OPERATIONAL_FLOW').orNull
                        ?: 'false')
                ['buss.vre.batch.xml', 'cons.vre.batch.xml'].each { appFileName ->
                    def appFile = project.file("${stitchRoot}/lineage/app/xml/${appFileName}")
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

        project.tasks.register("stitchLineage", xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: stitchLineage'
            dependsOn("mergeDirectFlows")
            dependsOn("verifyVreJavaLineageCoverage")
            style "${pipelineRoot}/6.stitch/src/main/xsl/stitch-lineage.xsl"
            input "${mergeRoot}/direct-flows.merged.xml"
            output "${stitchRoot}/stitched-lineage.xml"
            outputExtension.set('.xml')
            outputFormat.set('beautified')
            param('table-index-uri', project.file("${stitchRoot}/lineage").toURI().toString() + '?select=table-index.*.xir;on-error=ignore')
            doFirst {
                project.delete(project.file("${stitchRoot}/stitched-lineage.xml"))
            }
            outputs.upToDateWhen { !cleanRequested }
        }

        def stitchedLineageFile = project.file("${stitchRoot}/stitched-lineage.xml")
        project.tasks.register("carryAppXirToValidation", copyTaskClass) {
            group = 'lineage'
            description = 'Carry per-processor app lineage artifacts from stitch phase.'
            dependsOn("stitchLineage")
            from("${stitchRoot}/lineage/app/xir")
            into("${validateRoot}/lineage/app/xir")
            include("**/*.xir")
        }

        project.tasks.register("validateStitchLinkReferences") {
            group = 'lineage'
            description = 'Validate stitch-link direct-flow references with streaming XML scan.'
            dependsOn("stitchLineage")
            inputs.file(stitchedLineageFile)
            outputs.file(project.file("${validateRoot}/stitch-link-reference-validation.marker"))
            onlyIf { !cfg.skipValidations }
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

                def markerFile = project.file("${validateRoot}/stitch-link-reference-validation.marker")
                markerFile.parentFile.mkdirs()
                markerFile.text = "ok\n"
            }
        }

        project.tasks.register("validateLineage", schematronTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: validateLineage'
            dependsOn("stitchLineage")
            dependsOn("validateStitchLinkReferences")
            schema "${pipelineRoot}/7.validate-lineage/src/main/schematron/validate-lineage.sch"
            source stitchedLineageFile
            outputDir.set(project.file(validateRoot))
            failOnError.set(true)
            expandText.set(true)
            workers.set(4)
            onlyIf { !cfg.skipValidations }
            doFirst {
                logger.lifecycle("Running stitched-lineage Schematron validation (skipLineageValidations=${cfg.skipValidations}).")
            }
        }

        project.tasks.register("carryAppXirToExport") {
            group = 'lineage'
            description = 'Carry per-processor app lineage artifacts from validation phase.'
            dependsOn("carryAppXirToValidation")
            doLast {
                project.copy {
                    from("${validateRoot}/lineage/app/xir")
                    into("${exportRoot}/lineage/app/xir")
                    include("**/*.xir")
                }
                project.copy {
                    from("${validateRoot}/lineage/app/xir")
                    into("${exportRoot}/lineage/app/txt")
                    include("**/*.xir")
                    rename '(.*)\\.xir', '$1.xir.txt'
                }
            }
        }

        project.tasks.register("exportGraphML", xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: exportGraphML'
            dependsOn("validateLineage")
            style "${pipelineRoot}/8.export/src/main/xsl/stitched-to-graphml.xsl"
            input "${stitchRoot}/stitched-lineage.xml"
            output "${exportRoot}/graphml/lineage.graphml"
            outputExtension.set('.graphml')
            outputFormat.set('beautified')
        }

        project.tasks.register("exportRDF", xsltTaskClass) {
            group = 'lineage'
            description = 'Lifecycle stage: exportRDF'
            dependsOn("validateLineage")
            style "${pipelineRoot}/8.export/src/main/xsl/stitched-to-rdf.xsl"
            input "${stitchRoot}/stitched-lineage.xml"
            output "${exportRoot}/rdf/lineage.rdf"
            outputExtension.set('.rdf')
            outputFormat.set('beautified')
        }

        project.tasks.register("exportJsonForGraph", xsltTaskClass) {
            group = 'lineage'
            description = 'Export JSON projection for graph layout consumer.'
            dependsOn("validateLineage")
            style "${pipelineRoot}/8.export/src/main/xsl/stitched-to-json.xsl"
            input "${stitchRoot}/stitched-lineage.xml"
            output "${exportRoot}/json/lineage.json"
        }

        project.tasks.register('addLayout', pythonRunnerTaskClass) { t ->
            group = 'lineage'
            description = 'Add graph layout enrichment to exported lineage JSON files.'
            dependsOn("exportJsonForGraph")
            t.script = project.file("${pipelineRoot}/8.export/src/python/main.py")
            t.requirements = project.file("${pipelineRoot}/8.export/src/python/requirements.txt")
            t.workDir = project.file("${exportRoot}/graph")
            t.args = ["${exportRoot}/json", "${exportRoot}/graph"] as String[]
        }

        def appXirSourceDir = "${exportRoot}/lineage/app/xir"
        project.tasks.register("exportAppGraphML", xsltTaskClass) {
            group = 'lineage'
            description = 'Export per-processor GraphML projections from app lineage artifacts.'
            dependsOn("carryAppXirToExport")
            style "${pipelineRoot}/8.export/src/main/xsl/app-to-graphml.xsl"
            source(project.fileTree(appXirSourceDir) {
                include '**/*.xir'
            })
            outputDir.set(project.file("${exportRoot}/app/graphml"))
            outputExtension.set('.graphml')
            outputFormat.set('beautified')
        }

        project.tasks.register("exportAppRDF", xsltTaskClass) {
            group = 'lineage'
            description = 'Export per-processor RDF projections from app lineage artifacts.'
            dependsOn("carryAppXirToExport")
            style "${pipelineRoot}/8.export/src/main/xsl/app-to-rdf.xsl"
            source(project.fileTree(appXirSourceDir) {
                include '**/*.xir'
            })
            outputDir.set(project.file("${exportRoot}/app/rdf"))
            outputExtension.set('.rdf')
            outputFormat.set('beautified')
        }

        project.tasks.register('exportAppJson', pythonRunnerTaskClass) { t ->
            group = 'lineage'
            description = 'Export per-processor JSON projections from per-processor GraphML outputs.'
            dependsOn("exportAppGraphML")
            t.script = project.file("${pipelineRoot}/8.export/src/python/app_graphml_to_json.py")
            t.requirements = project.file("${pipelineRoot}/8.export/src/python/requirements.txt")
            t.workDir = project.file("${exportRoot}/app/json")
            t.args = ["${exportRoot}/app/graphml", "${exportRoot}/app/json"] as String[]
        }

        project.tasks.register("exportLineageArtifacts") {
            group = 'lineage'
            description = 'Lifecycle stage: export lineages and projections.'
            dependsOn("exportGraphML", "exportRDF", "exportJsonForGraph", "addLayout")
            dependsOn("carryAppXirToExport", "exportAppGraphML", "exportAppRDF", "exportAppJson")
        }

        project.tasks.register("verifyPerProcessorExports") {
            group = 'lineage'
            description = 'Fail when per-processor export artifacts are missing.'
            dependsOn("exportLineageArtifacts")
            doLast {
                def graphmlFiles = project.fileTree("${exportRoot}/app/graphml") { include '**/*.graphml' }.files
                def rdfFiles = project.fileTree("${exportRoot}/app/rdf") { include '**/*.rdf' }.files
                def jsonFiles = project.fileTree("${exportRoot}/app/json") { include '**/*.json' }.files
                if (graphmlFiles.isEmpty() || rdfFiles.isEmpty() || jsonFiles.isEmpty()) {
                    throw new GradleException("Missing per-processor exports under ${exportRoot}/app/{graphml,json,rdf}")
                }
            }
        }

        project.tasks.register("publishLineage") {
            group = 'lineage'
            description = 'Lifecycle stage: publishLineage'
            dependsOn("exportLineageArtifacts")
            dependsOn("verifyPerProcessorExports")
            doLast {
                project.copy {
                    from(exportRoot)
                    into("${publishRoot}/artifacts")
                }
            }
        }

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

    private static Map<String, Object> resolveLineageConfig(Project project, LineagePipelineExtension ext) {
        def parseBool = { Object v ->
            def s = (v ?: '').toString().trim().toLowerCase()
            s in ['1', 'true', 'yes', 'y', 'on']
        }
        def sourceRoot = (ext.sourceRoot ?: project.rootProject.projectDir.parentFile.absolutePath).toString()
        def defaultBuildRoot = (ext.lineageBuildRoot
                ?: project.layout.buildDirectory.dir('lineage-uniform').get().asFile.absolutePath).toString()
        def buildRoot = (project.findProperty('buildRoot')
                ?: project.findProperty('lineageBuildRoot')
                ?: project.providers.environmentVariable('LINEAGE_BUILD_ROOT').orNull
                ?: defaultBuildRoot).toString()
        def skipValidations = parseBool(project.findProperty('skipLineageValidations') ?: project.providers.environmentVariable('SKIP_LINEAGE_VALIDATIONS').orNull ?: ext.skipLineageValidations)
        def schemaNames = (ext.schemaNames ?: ['buss', 'cons', 'sdp', 'dsa', 'sdp_staging', 'dsa_staging']).collect { it.toString() }
        def architectureModelFile = (ext.architectureModelFile ?: "${sourceRoot}/architecture/vortex-archimate-risk.xml").toString()
        def architectureProcessedFile = (ext.architectureProcessedFile ?: "${buildRoot}/6.stitch/architecture/${new File(architectureModelFile).name}").toString()
        def repos = ext.repos.items ?: []
        if (repos.isEmpty()) {
            throw new GradleException("lineagePipeline.repos must contain at least one repo { ... } entry.")
        }

        def repoConfigs = repos.collect { RepoConfig repo ->
            def uri = repo.uri.get()?.toString()?.trim()
            if (!uri) {
                throw new GradleException("Each lineagePipeline repo must set uri.")
            }
            def ref = repo.ref.get()?.toString()?.trim() ?: "master"
            def repoName = deriveRepoName(uri)
            def repoDir = new File(sourceRoot, repoName)

            if (repo.sourceSets.isEmpty()) {
                throw new GradleException("Repo ${uri} must define at least one sourceSet(...).")
            }

            def sourceSets = repo.sourceSets.collect { SourceSetConfig sourceSet ->
                def sourceSetName = sourceSet.name?.trim()
                if (!sourceSetName) {
                    throw new GradleException("sourceSet name must be non-empty.")
                }

                def parserPlugin = sourceSet.parserPlugin.get()?.toString()?.trim()
                if (!parserPlugin) {
                    throw new GradleException("sourceSet '${sourceSetName}' must set parserPlugin.")
                }
                if (!isAcceptedParserPlugin(parserPlugin)) {
                    throw new GradleException("Unsupported parser plugin '${parserPlugin}' for sourceSet '${sourceSetName}'. Accepted: ${ANTLR_PLUGIN_ID} and ${ANTLR_PLUGIN_ID}.*")
                }

                def includes = (sourceSet.includes.get() ?: []).collect { it.toString() }.findAll { !it.isBlank() }
                if (includes.isEmpty()) {
                    throw new GradleException("sourceSet '${sourceSetName}' must provide includes.")
                }

                def sourceDirectoryRaw = sourceSet.sourceDirectory.get()
                if (sourceDirectoryRaw == null) {
                    throw new GradleException("sourceSet '${sourceSetName}' must set sourceDirectory.")
                }
                def sourceDirectoryRelative = normalizeSourceDirectory(project, sourceDirectoryRaw)
                def parserKind = parserKindForPlugin(parserPlugin)

                [
                        name: sourceSetName,
                        parserPlugin: parserPlugin,
                        parserKind: parserKind,
                        includes: includes,
                        sourceDirectoryRelative: sourceDirectoryRelative,
                        sourceDirectoryAbsolute: new File(repoDir, sourceDirectoryRelative).absolutePath,
                        repoName: repoName,
                        repoUri: uri,
                        repoRef: ref,
                        repoDirectory: repoDir.absolutePath
                ]
            }

            [
                    name: repoName,
                    uri: uri,
                    ref: ref,
                    directory: repoDir.absolutePath,
                    sourceSets: sourceSets
            ]
        }

        def allSourceSets = repoConfigs.collectMany { it.sourceSets }
        def sqlSourceSets = allSourceSets.findAll { it.parserKind in ['plsql', 'sas', 'tsql'] }
        def javaSourceSets = allSourceSets.findAll { it.parserKind == 'java' }

        return [
                sourceRoot: sourceRoot,
                buildRoot: buildRoot,
                skipValidations: skipValidations,
                schemaNames: schemaNames,
                schemaPat: "{${schemaNames.join(',')}}",
                repos: repoConfigs,
                sourceSets: allSourceSets,
                sqlSourceSets: sqlSourceSets,
                javaSourceSets: javaSourceSets,
                sqlEnabled: !sqlSourceSets.isEmpty(),
                javaEnabled: !javaSourceSets.isEmpty(),
                javaSourceSetNames: javaSourceSets.collect { it.name },
                architectureModelFile: architectureModelFile,
                architectureProcessedFile: architectureProcessedFile
        ]
    }

    private static void registerRepoSyncTasks(Project project, Map<String, Object> cfg) {
        def repos = (cfg.repos ?: []) as List<Map<String, Object>>
        repos.each { repo ->
            def taskSuffix = toTaskSuffix(repo.name.toString())
            project.tasks.register("syncLineageRepo${taskSuffix}") {
                group = "lineage"
                description = "Clone or update lineage source repo ${repo.uri} at ref ${repo.ref}."
                doLast {
                    def repoDir = project.file(repo.directory.toString())
                    def updateExistingRepos = ((project.findProperty('lineageSyncUpdate')
                            ?: project.providers.environmentVariable('LINEAGE_SYNC_UPDATE').orNull
                            ?: 'false').toString().trim().toLowerCase()) in ['1', 'true', 'yes', 'y', 'on']
                    if (!repoDir.exists()) {
                        repoDir.parentFile.mkdirs()
                        project.providers.exec {
                            commandLine("git", "clone", "--branch", repo.ref.toString(), repo.uri.toString(), repoDir.absolutePath)
                        }.result.get().assertNormalExitValue()
                    } else {
                        project.providers.exec {
                            commandLine("git", "-C", repoDir.absolutePath, "checkout", repo.ref.toString())
                        }.result.get().assertNormalExitValue()
                        if (updateExistingRepos) {
                            project.providers.exec {
                                commandLine("git", "-C", repoDir.absolutePath, "fetch", "--all", "--prune")
                            }.result.get().assertNormalExitValue()
                            project.providers.exec {
                                commandLine("git", "-C", repoDir.absolutePath, "pull", "--ff-only", "origin", repo.ref.toString())
                            }.result.get().assertNormalExitValue()
                        } else {
                            project.logger.lifecycle("Skipping remote sync for existing repo ${repoDir.name}. Enable with -PlineageSyncUpdate=true or LINEAGE_SYNC_UPDATE=true.")
                        }
                    }
                }
            }
        }

        project.tasks.register("syncLineageRepos") {
            group = "lineage"
            description = "Clone or update all configured lineage source repositories."
            dependsOn(repos.collect { "syncLineageRepo${toTaskSuffix(it.name.toString())}" })
        }
    }

    private static String parserKindForPlugin(String parserPluginId) {
        if (parserPluginId.endsWith(".java")) return "java"
        if (parserPluginId.endsWith(".plsql")) return "plsql"
        if (parserPluginId.endsWith(".sas")) return "sas"
        if (parserPluginId.endsWith(".tsql")) return "tsql"
        if (parserPluginId == ANTLR_PLUGIN_ID || parserPluginId.startsWith("${ANTLR_PLUGIN_ID}.")) return "antlr"
        throw new GradleException("Unsupported parser plugin '${parserPluginId}'. Accepted: ${ANTLR_PLUGIN_ID} and ${ANTLR_PLUGIN_ID}.*")
    }

    private static boolean isAcceptedParserPlugin(String parserPluginId) {
        parserPluginId == ANTLR_PLUGIN_ID || parserPluginId.startsWith("${ANTLR_PLUGIN_ID}.")
    }

    private static String normalizeSourceDirectory(Project project, Object rawSourceDirectory) {
        if (rawSourceDirectory instanceof File) {
            def fileValue = rawSourceDirectory as File
            if (!fileValue.isAbsolute()) {
                return fileValue.path
            }
            def projectRoot = project.rootProject.projectDir.absoluteFile.toPath().normalize()
            def sourcePath = fileValue.absoluteFile.toPath().normalize()
            if (sourcePath.startsWith(projectRoot)) {
                return projectRoot.relativize(sourcePath).toString()
            }
            return fileValue.absolutePath
        }
        def text = rawSourceDirectory.toString()
        if (!text?.trim()) {
            throw new GradleException("sourceDirectory value cannot be blank.")
        }
        return text
    }

    private static String deriveRepoName(String repoUri) {
        def trimmed = repoUri.trim()
        def last = trimmed.tokenize('/').last()
        def withoutGit = last.endsWith('.git') ? last[0..-5] : last
        return withoutGit
    }

    private static String toTaskSuffix(String key) {
        key.split(/[^A-Za-z0-9]+/)
                .findAll { !it.isBlank() }
                .collect { it.capitalize() }
                .join('')
    }
}
