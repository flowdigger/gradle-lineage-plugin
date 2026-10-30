package name.jurgenei.gradle.lineage

import org.gradle.api.GradleException
import org.gradle.api.Project

class LineagePipelineContext {
    Project project
    Map<String, Object> cfg
    LineagePipelineExtension ext

    Class<?> xmlAstPlsqlTaskClass
    Class<?> xmlAstJavaTaskClass
    Class<?> xsltTaskClass
    Class<?> schematronTaskClass
    Class<?> ooxmlTaskClass
    Class<?> pythonRunnerTaskClass
    Class<?> copyTaskClass

    String buildRoot
    String parseRoot
    String observeRoot
    String directFlowRoot
    String validateDirectFlowRoot
    String mergeRoot
    String stitchRoot
    String validateRoot
    String exportRoot
    String publishRoot
    String sqlIndexRoot
    String pipelineRoot

    List<Map<String, Object>> sqlSourceSets
    List<Map<String, Object>> javaSourceSets
    List<String> javaSourceSetNames
    Map<String, String> javaTaskSuffixes
    List<String> schemaNames
    String sqlPrimarySourceSet
    boolean cleanRequested

    Closure<String> toTaskSuffix
    Closure<Boolean> parseBool
    Closure<String> toCollectionUri

    static LineagePipelineContext create(Project project, Map<String, Object> cfg, LineagePipelineExtension ext) {
        project.pluginManager.apply('name.jurgenei.gradle.xml')
        project.pluginManager.apply('name.jurgenei.gradle.ooxml')
        project.pluginManager.apply('name.jurgenei.gradle.python')
        if (cfg.sqlEnabled) {
            project.pluginManager.apply('name.jurgenei.gradle.antlr.plsql')
        }
        if (cfg.javaEnabled) {
            project.pluginManager.apply('name.jurgenei.gradle.antlr.java')
        }

        def ctx = new LineagePipelineContext(project: project, cfg: cfg, ext: ext)
        ctx.xmlAstPlsqlTaskClass = cfg.sqlEnabled ? resolveTaskClass(project, 'name.jurgenei.gradle.antlr.XmlAstPlsqlGradleTask') : null
        ctx.xmlAstJavaTaskClass = cfg.javaEnabled ? resolveTaskClass(project, 'name.jurgenei.gradle.antlr.XmlAstJavaGradleTask') : null
        ctx.xsltTaskClass = resolveTaskClass(project, 'name.jurgenei.gradle.xml.XsltTask')
        ctx.schematronTaskClass = resolveTaskClass(project, 'name.jurgenei.gradle.xml.SchematronTask')
        ctx.ooxmlTaskClass = resolveTaskClass(project, 'name.jurgenei.gradle.ooxml.OoXmlToCanonicalTask')
        ctx.pythonRunnerTaskClass = resolveTaskClass(project, 'name.jurgenei.gradle.python.PythonRunnerTask')
        ctx.copyTaskClass = resolveTaskClass(project, 'org.gradle.api.tasks.Copy')

        ctx.toTaskSuffix = { String key -> LineageTaskNames.toTaskSuffix(key) }
        ctx.parseBool = { Object v ->
            def s = (v ?: '').toString().trim().toLowerCase()
            s in ['1', 'true', 'yes', 'y', 'on']
        }
        ctx.cleanRequested = project.gradle.startParameter.taskNames.any { taskName ->
            taskName == 'clean' || taskName.endsWith(':clean') || taskName == 'cleanAllLineage' || taskName.endsWith(':cleanAllLineage')
        }
        def includedPluginBuild = project.gradle.includedBuilds.find { it.name == 'gradle-lineage-plugin' }
        ctx.pipelineRoot = (project.findProperty('lineagePluginPipelineRoot')
                ?: project.providers.environmentVariable('LINEAGE_PLUGIN_PIPELINE_ROOT').orNull
                ?: (includedPluginBuild != null ? new File(includedPluginBuild.projectDir, 'pipeline').absolutePath : "${project.rootProject.projectDir}/build-logic/pipeline"))
                .toString()
        ctx.toCollectionUri = { String dirPath, String selectPattern ->
            def dirUri = project.file(dirPath).toURI().toString()
            def normalized = dirUri.endsWith('/') ? dirUri : "${dirUri}/"
            "${normalized}?select=${selectPattern};recurse=yes;on-error=ignore"
        }

        ctx.buildRoot = cfg.buildRoot.toString()
        ctx.parseRoot = "${ctx.buildRoot}/1.parse"
        ctx.observeRoot = "${ctx.buildRoot}/2.observe"
        ctx.directFlowRoot = "${ctx.buildRoot}/3.direct-flow"
        ctx.validateDirectFlowRoot = "${ctx.buildRoot}/4.validate-direct-flow"
        ctx.mergeRoot = "${ctx.buildRoot}/5.merge"
        ctx.stitchRoot = "${ctx.buildRoot}/6.stitch"
        ctx.validateRoot = "${ctx.buildRoot}/7.validate-lineage"
        ctx.exportRoot = "${ctx.buildRoot}/8.export"
        ctx.publishRoot = "${ctx.buildRoot}/9.publish"
        ctx.sqlIndexRoot = "${ctx.mergeRoot}/sql-index"

        ctx.sqlSourceSets = (cfg.sqlSourceSets ?: []) as List<Map<String, Object>>
        ctx.javaSourceSets = (cfg.javaSourceSets ?: []) as List<Map<String, Object>>
        ctx.javaSourceSetNames = (cfg.javaSourceSetNames ?: []).collect { it.toString() }.sort()
        ctx.javaTaskSuffixes = ctx.javaSourceSetNames.collectEntries { [(it): ctx.toTaskSuffix(it)] } as Map<String, String>
        ctx.schemaNames = (cfg.schemaNames ?: []).collect { it.toString() }
        ctx.sqlPrimarySourceSet = ctx.sqlSourceSets ? ctx.sqlSourceSets[0].name.toString() : null

        return ctx
    }

    private static Class<?> resolveTaskClass(Project project, String className) {
        def candidates = [
                project.buildscript.classLoader,
                Thread.currentThread().contextClassLoader,
                LineagePipelineContext.classLoader
        ].findAll { it != null }

        for (def classLoader : candidates) {
            try {
                return classLoader.loadClass(className)
            } catch (ClassNotFoundException ignored) {
                // Try next candidate classloader.
            }
        }

        throw new GradleException("Required task class '${className}' not found in plugin/buildscript classpath.")
    }
}
