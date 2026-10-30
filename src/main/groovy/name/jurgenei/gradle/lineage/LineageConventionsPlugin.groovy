package name.jurgenei.gradle.lineage

import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project

class LineageConventionsPlugin implements Plugin<Project> {
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
            LineageConfigResolver.resolve(project, ext)
        }

        project.afterEvaluate {
            def cfg = LineageConfigResolver.resolve(project, ext)
            LineageRepoSyncTasks.register(project, cfg)
            LineagePipelineTasks.register(project, cfg, ext)
            LineageGlobalTasks.register(project, ext)
            project.rootProject.ext.lineage = cfg
        }
    }
}
