package org.flowdigger.gradle.lineage

import org.gradle.api.GradleException
import org.gradle.api.Project

class LineageConfigResolver {
    private static final String ANTLR_PLUGIN_ID = 'org.flowdigger.gradle.antlr'

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
        def legacySchemaNames = normalizeSchemaNames(ext.schemaNames as List<?>, false)
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
        def defaultRepoRef = resolveDefaultRepoRef(project)

        def repoConfigs = repos.collect { RepoConfig repo ->
            def uri = repo.uri.get()?.toString()?.trim()
            if (!uri) {
                throw new GradleException("Each lineagePipeline repo must set uri.")
            }
            def configuredRef = repo.ref.get()?.toString()?.trim()
            def ref = configuredRef ?: defaultRepoRef.value
            def refSource = configuredRef ? "repo.ref" : defaultRepoRef.source
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
                def configuredSchemas = normalizeSchemaNames(sourceSet.schemas.get() as List<?>, true)
                def derivedSchemas = isSqlParserKind(parserKind)
                        ? deriveSchemaNames(new File(repoDir, sourceDirectoryRelative))
                        : []
                def effectiveSqlSchemas = configuredSchemas
                        ? configuredSchemas
                        : (derivedSchemas ? derivedSchemas : legacySchemaNames)
                def sqlSchemaNames = normalizeSchemaNames(effectiveSqlSchemas, false)

                [
                        name: sourceSetName,
                        parserPlugin: parserPlugin,
                        parserKind: parserKind,
                        includes: includes,
                        sourceDirectoryRelative: sourceDirectoryRelative,
                        sourceDirectoryAbsolute: new File(repoDir, sourceDirectoryRelative).absolutePath,
                        sqlSchemaNames: sqlSchemaNames,
                        repoName: repoName,
                        repoUri: uri,
                        repoRef: ref,
                        repoRefSource: refSource,
                        repoDirectory: repoDir.absolutePath
                ]
            }

            [
                    name: repoName,
                    uri: uri,
                    ref: ref,
                    refSource: refSource,
                    directory: repoDir.absolutePath,
                    sourceSets: sourceSets
            ]
        }

        def allSourceSets = repoConfigs.collectMany { it.sourceSets }
        def sqlSourceSets = allSourceSets.findAll { it.parserKind in ['plsql', 'sas', 'tsql'] }
        def javaSourceSets = allSourceSets.findAll { it.parserKind == 'java' }
        def schemaNames = normalizeSchemaNames(sqlSourceSets.collectMany { it.sqlSchemaNames as List<?> }, false)
        if (schemaNames.isEmpty()) {
            schemaNames = legacySchemaNames
        }

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

    private static boolean isSqlParserKind(String parserKind) {
        parserKind in ['plsql', 'sas', 'tsql']
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

    private static Map<String, String> resolveDefaultRepoRef(Project project) {
        def override = (project.findProperty('lineageRepoRef')
                ?: project.providers.environmentVariable('LINEAGE_REPO_REF').orNull
                ?: project.findProperty('lineageSampleRef')
                ?: project.providers.environmentVariable('LINEAGE_SAMPLE_REF').orNull)
                ?.toString()?.trim()
        if (override) {
            return [value: override, source: "lineageRepoRef/LINEAGE_REPO_REF override"]
        }
        def branch = detectCurrentBranch(project)
        if (branch) {
            return [value: branch, source: "current git branch"]
        }
        return [value: "main", source: "fallback"]
    }

    private static String detectCurrentBranch(Project project) {
        try {
            def output = project.providers.exec {
                commandLine('git', 'rev-parse', '--abbrev-ref', 'HEAD')
                workingDir(project.rootProject.projectDir)
            }.standardOutput.asText.getOrElse('').trim()
            return output && output != 'HEAD' ? output : null
        } catch (Exception ignored) {
            return null
        }
    }

    private static List<String> deriveSchemaNames(File sourceDirectory) {
        if (sourceDirectory == null || !sourceDirectory.exists() || !sourceDirectory.isDirectory()) {
            return []
        }
        def childFolders = sourceDirectory.listFiles()?.findAll { it.isDirectory() }?.collect { it.name } ?: []
        return normalizeSchemaNames(childFolders, false).sort()
    }

    private static List<String> normalizeSchemaNames(List<?> values, boolean keepEmpty) {
        def out = []
        (values ?: []).each { raw ->
            if (raw == null) {
                return
            }
            def normalized = raw.toString().trim().toLowerCase()
            if (normalized.isEmpty() && !keepEmpty) {
                return
            }
            out << normalized
        }
        return out.unique()
    }
}
