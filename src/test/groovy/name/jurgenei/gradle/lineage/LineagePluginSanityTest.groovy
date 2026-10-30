package name.jurgenei.gradle.lineage

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

import static org.gradle.testkit.runner.TaskOutcome.SUCCESS
import static org.junit.jupiter.api.Assertions.assertEquals
import static org.junit.jupiter.api.Assertions.assertFalse
import static org.junit.jupiter.api.Assertions.assertTrue

class LineagePluginSanityTest {
    @TempDir
    File testProjectDir

    @Test
    void "registers lifecycle tasks and keeps publish graph reachable"() {
        writeSettingsWithBuilds(testProjectDir)
        writeLineageBuild(testProjectDir)

        def tasksResult = runner(testProjectDir)
                .withArguments('tasks', '--all')
                .build()

        [
                'parseLineageSources',
                'extractLineageObservations',
                'deriveDirectFlows',
                'validateDirectFlows',
                'mergeDirectFlows',
                'stitchLineage',
                'validateLineage',
                'exportLineageArtifacts',
                'publishLineage'
        ].each { taskName ->
            assertTrue(tasksResult.output.contains(taskName), "Expected task not found: ${taskName}")
        }

        def dryRun = runner(testProjectDir)
                .withArguments('publishLineage', '-m')
                .build()

        ['validateDirectFlows', 'mergeDirectFlows', 'stitchLineage', 'validateLineage', 'exportLineageArtifacts', 'publishLineage'].each { taskName ->
            assertTrue(dryRun.output.contains(":${taskName} SKIPPED"), "Expected dry-run graph to include ${taskName}")
        }
    }

    @Test
    void "clean preserves parse stage and removes later stages"() {
        writeSettingsWithBuilds(testProjectDir)
        writeLineageBuild(testProjectDir)

        def buildRoot = new File(testProjectDir, 'lineage-uniform')
        new File(buildRoot, '1.parse/sql').mkdirs()
        new File(buildRoot, '2.observe/sql').mkdirs()
        new File(buildRoot, '9.publish/artifacts').mkdirs()
        new File(buildRoot, '2.observe/sql/probe.txt').text = 'probe'

        def result = runner(testProjectDir)
                .withArguments('clean')
                .build()

        assertEquals(SUCCESS, result.task(':clean').outcome)
        assertTrue(new File(buildRoot, '1.parse').exists(), "1.parse must be preserved")
        assertFalse(new File(buildRoot, '2.observe').exists(), "2.observe must be removed")
        assertFalse(new File(buildRoot, '9.publish').exists(), "9.publish must be removed")
    }

    private static GradleRunner runner(File projectDir) {
        GradleRunner.create()
                .withProjectDir(projectDir)
                .withPluginClasspath()
                .forwardOutput()
    }

    private static void writeSettingsWithBuilds(File projectDir) {
        def gradleRoot = new File(System.getProperty('user.dir')).parentFile
        def xmlBuild = new File(gradleRoot, 'gradle-xml-plugin').absolutePath.replace('\\', '\\\\')
        def ooxmlBuild = new File(gradleRoot, 'gradle-ooxml-plugin').absolutePath.replace('\\', '\\\\')
        def pythonBuild = new File(gradleRoot, 'gradle-python-plugin').absolutePath.replace('\\', '\\\\')
        def antlrJavaBuild = new File(gradleRoot, 'gradle-antlr-java-plugin').absolutePath.replace('\\', '\\\\')
        def antlrPlsqlBuild = new File(gradleRoot, 'gradle-antlr-plsql-plugin').absolutePath.replace('\\', '\\\\')
        new File(projectDir, 'settings.gradle').text = """
pluginManagement {
  includeBuild('${xmlBuild}')
  includeBuild('${ooxmlBuild}')
  includeBuild('${pythonBuild}')
  includeBuild('${antlrJavaBuild}')
  includeBuild('${antlrPlsqlBuild}')
}

rootProject.name = 'lineage-plugin-sanity'
""".stripIndent()
    }

    private static void writeLineageBuild(File projectDir) {
        def pipelineRoot = new File(System.getProperty('user.dir'), 'pipeline').absolutePath.replace('\\', '\\\\')
        new File(projectDir, 'build.gradle').text = """
plugins {
  id 'base'
  id 'name.jurgenei.gradle.xml' apply false
  id 'name.jurgenei.gradle.ooxml' apply false
  id 'name.jurgenei.gradle.python' apply false
  id 'name.jurgenei.gradle.antlr.java' apply false
  id 'name.jurgenei.gradle.antlr.plsql' apply false
  id 'name.jurgenei.gradle.lineage'
}

ext.set('lineagePluginPipelineRoot', '${pipelineRoot}')

lineagePipeline {
  sourceRoot = rootProject.projectDir.absolutePath
  lineageBuildRoot = rootProject.file('lineage-uniform').absolutePath
  repos {
    repo {
      uri.set('https://github.com/example/demo-lineage.git')
      ref.set('main')
      sourceSet('java') {
        parserPlugin.set('name.jurgenei.gradle.antlr.java')
        sourceDirectory.set(file('src/main/java'))
        includes.set(['**/*.java'])
      }
    }
  }
}
""".stripIndent()
        new File(projectDir, 'src/main/java').mkdirs()
    }
}
