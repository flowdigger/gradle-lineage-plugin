package name.jurgenei.gradle.lineage

import org.gradle.api.Project

class LineageRepoSyncTasks {
    static void register(Project project, Map<String, Object> cfg) {
        def repos = (cfg.repos ?: []) as List<Map<String, Object>>
        repos.each { repo ->
            def taskSuffix = LineageTaskNames.toTaskSuffix(repo.name.toString())
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
                            commandLine("git", "-C", repoDir.absolutePath, "fetch", "--all", "--prune")
                        }.result.get().assertNormalExitValue()
                        project.providers.exec {
                            commandLine("git", "-C", repoDir.absolutePath, "checkout", repo.ref.toString())
                        }.result.get().assertNormalExitValue()
                        if (updateExistingRepos) {
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
            dependsOn(repos.collect { "syncLineageRepo${LineageTaskNames.toTaskSuffix(it.name.toString())}" })
        }
    }
}
