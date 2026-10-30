package name.jurgenei.gradle.lineage

import org.gradle.api.GradleException
import org.gradle.api.Project

class LineageConfigResolver {
    private static final String ANTLR_PLUGIN_ID = 'name.jurgenei.gradle.antlr'

    static Map<String, Object> resolve(Project project, LineagePipelineExtension ext) {
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
        def appSticherStylesheet = normalizeOptionalFilePath(project,
                project.findProperty('appSticherStylesheet')
                        ?: project.providers.environmentVariable('APP_STICHER_STYLESHEET').orNull
                        ?: ext.appSticherStylesheet,
                'appSticherStylesheet')
        if (appSticherStylesheet != null && !new File(appSticherStylesheet).exists()) {
            throw new GradleException("Configured appSticherStylesheet does not exist: ${appSticherStylesheet}")
        }
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
                architectureProcessedFile: architectureProcessedFile,
                appSticherStylesheet: appSticherStylesheet
        ]
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

    private static String normalizeOptionalFilePath(Project project, Object rawPath, String label) {
        if (rawPath == null) {
            return null
        }
        if (rawPath instanceof File) {
            return (rawPath as File).absolutePath
        }
        def text = rawPath.toString().trim()
        if (text.isEmpty()) {
            return null
        }
        try {
            return project.file(text).absolutePath
        } catch (Exception ex) {
            throw new GradleException("Invalid ${label} path '${text}': ${ex.message}", ex)
        }
    }

    private static String deriveRepoName(String repoUri) {
        def trimmed = repoUri.trim()
        def last = trimmed.tokenize('/').last()
        def withoutGit = last.endsWith('.git') ? last[0..-5] : last
        return withoutGit
    }
}
