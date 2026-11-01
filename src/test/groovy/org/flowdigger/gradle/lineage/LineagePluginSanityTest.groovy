package org.flowdigger.gradle.lineage

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

import static org.gradle.testkit.runner.TaskOutcome.SUCCESS
import static org.junit.jupiter.api.Assertions.assertEquals
import static org.junit.jupiter.api.Assertions.assertFalse
import static org.junit.jupiter.api.Assertions.assertTrue

class LineagePluginSanityTest {
    private static final String XML_PLUGIN_VERSION = '0.1.15'
    private static final String OOXML_PLUGIN_VERSION = '0.1.12'
    private static final String PYTHON_PLUGIN_VERSION = '0.1.4'
    private static final String ANTLR_JAVA_PLUGIN_VERSION = '0.1.4'
    private static final String ANTLR_PLSQL_PLUGIN_VERSION = '0.1.8'

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

    @Test
    void "accepts configured appSticherStylesheet override path"() {
        writeSettingsWithBuilds(testProjectDir)
        def customStylesheet = new File(testProjectDir, 'lineage/call-app.custom.xsl')
        customStylesheet.parentFile.mkdirs()
        customStylesheet.text = """
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
  <xsl:template match="/">
    <ok/>
  </xsl:template>
</xsl:stylesheet>
""".stripIndent()
        writeLineageBuild(testProjectDir, customStylesheet.absolutePath)

        def result = runner(testProjectDir)
                .withArguments('tasks', '--all')
                .build()

        assertTrue(result.output.contains('publishLineage'))
    }

    @Test
    void "fails fast on missing appSticherStylesheet override path"() {
        writeSettingsWithBuilds(testProjectDir)
        writeLineageBuild(testProjectDir, new File(testProjectDir, 'missing/call-app.xsl').absolutePath)

        def result = runner(testProjectDir)
                .withArguments('tasks', '--all')
                .buildAndFail()

        assertTrue(result.output.contains('Configured appSticherStylesheet does not exist'))
    }

    private static GradleRunner runner(File projectDir) {
        GradleRunner.create()
                .withProjectDir(projectDir)
                .withPluginClasspath()
                .forwardOutput()
    }

    private static void writeSettingsWithBuilds(File projectDir) {
        new File(projectDir, 'settings.gradle').text = """
rootProject.name = 'lineage-plugin-sanity'
""".stripIndent()
    }

    private static void writeLineageBuild(File projectDir, String appSticherStylesheet = null) {
        def pipelineRoot = new File(System.getProperty('user.dir'), 'pipeline').absolutePath.replace('\\', '\\\\')
        def escapedOverridePath = appSticherStylesheet != null ? appSticherStylesheet.replace('\\', '\\\\') : null
        def optionalOverrideBlock = escapedOverridePath != null ? "  appSticherStylesheet = '${escapedOverridePath}'\n" : ""
        new File(projectDir, 'build.gradle').text = """
plugins {
  id 'base'
  id 'org.flowdigger.gradle.xml' version '${XML_PLUGIN_VERSION}' apply false
  id 'org.flowdigger.gradle.ooxml' version '${OOXML_PLUGIN_VERSION}' apply false
  id 'org.flowdigger.gradle.python' version '${PYTHON_PLUGIN_VERSION}' apply false
  id 'org.flowdigger.gradle.antlr.java' version '${ANTLR_JAVA_PLUGIN_VERSION}' apply false
  id 'org.flowdigger.gradle.antlr.plsql' version '${ANTLR_PLSQL_PLUGIN_VERSION}' apply false
  id 'org.flowdigger.gradle.lineage'
}

ext.set('lineagePluginPipelineRoot', '${pipelineRoot}')

lineagePipeline {
  sourceRoot = rootProject.projectDir.absolutePath
  lineageBuildRoot = rootProject.file('lineage-uniform').absolutePath
${optionalOverrideBlock}
  repos {
    repo {
      uri.set('https://github.com/example/demo-lineage.git')
      ref.set('main')
      sourceSet('java') {
        parserPlugin.set('org.flowdigger.gradle.antlr.java')
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
