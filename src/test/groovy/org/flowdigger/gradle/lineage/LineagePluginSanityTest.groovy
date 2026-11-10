package org.flowdigger.gradle.lineage

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
        def testKitDir = new File(System.getProperty('java.io.tmpdir'), "lineage-gradle-testkit/${java.util.UUID.randomUUID()}")
        testKitDir.mkdirs()
        GradleRunner.create()
                .withProjectDir(projectDir)
                .withTestKitDir(testKitDir)
                .withPluginClasspath()
                .forwardOutput()
    }

    private static void writeSettingsWithBuilds(File projectDir) {
        writeStubCompanionPlugins(projectDir)
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
  id 'org.flowdigger.xml' apply false
  id 'org.flowdigger.ooxml' apply false
  id 'org.flowdigger.python' apply false
  id 'org.flowdigger.antlr.java' apply false
  id 'org.flowdigger.antlr.plsql' apply false
  id 'org.flowdigger.lineage'
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
        parserPlugin.set('org.flowdigger.antlr.java')
        sourceDirectory.set(file('src/main/java'))
        includes.set(['**/*.java'])
      }
    }
  }
}
""".stripIndent()
        new File(projectDir, 'src/main/java').mkdirs()
    }

    private static void writeStubCompanionPlugins(File projectDir) {
        def buildSrcDir = new File(projectDir, 'buildSrc')
        buildSrcDir.mkdirs()
        new File(buildSrcDir, 'build.gradle').text = """
plugins {
  id 'groovy-gradle-plugin'
  id 'java-gradle-plugin'
}

repositories {
  mavenCentral()
  gradlePluginPortal()
}

dependencies {
  implementation gradleApi()
  implementation localGroovy()
}

gradlePlugin {
  plugins {
    xml {
      id = 'org.flowdigger.xml'
      implementationClass = 'org.flowdigger.stub.NoopXmlPlugin'
    }
    ooxml {
      id = 'org.flowdigger.ooxml'
      implementationClass = 'org.flowdigger.stub.NoopOoxmlPlugin'
    }
    python {
      id = 'org.flowdigger.python'
      implementationClass = 'org.flowdigger.stub.NoopPythonPlugin'
    }
    antlrJava {
      id = 'org.flowdigger.antlr.java'
      implementationClass = 'org.flowdigger.stub.NoopAntlrJavaPlugin'
    }
    antlrPlsql {
      id = 'org.flowdigger.antlr.plsql'
      implementationClass = 'org.flowdigger.stub.NoopAntlrPlsqlPlugin'
    }
  }
}
""".stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/stub').mkdirs()
new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/xml').mkdirs()
new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/ooxml').mkdirs()
new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/python').mkdirs()
new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/antlr').mkdirs()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/stub/NoopPlugins.groovy').text = '''
package org.flowdigger.stub

import org.gradle.api.Plugin
import org.gradle.api.Project

class NoopXmlPlugin implements Plugin<Project> { void apply(Project project) { } }
class NoopOoxmlPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.tasks.register('ooxmlToCanonical', org.flowdigger.gradle.ooxml.OoXmlToCanonicalTask)
    }
}
class NoopPythonPlugin implements Plugin<Project> { void apply(Project project) { } }
class NoopAntlrJavaPlugin implements Plugin<Project> { void apply(Project project) { } }
class NoopAntlrPlsqlPlugin implements Plugin<Project> { void apply(Project project) { } }
'''.stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/stub/DynamicStubTask.groovy').text = '''
package org.flowdigger.stub

import org.gradle.api.DefaultTask
import org.gradle.api.tasks.TaskAction

class DynamicStubTask extends DefaultTask {
    private final Map<String, Object> values = [:]

    Object propertyMissing(String name) {
values.computeIfAbsent(name) { new MutableStub() }
    }

    void propertyMissing(String name, Object value) {
values[name] = value
    }

    Object methodMissing(String name, Object args) {
null
    }

    @TaskAction
    void run() {
// no-op
    }
}

class MutableStub {
    private final Map<String, Object> nested = [:]
    Object value

    Object propertyMissing(String name) {
        nested.computeIfAbsent(name) { new MutableStub() }
    }

    void propertyMissing(String name, Object value) {
        nested[name] = value
    }

    Object methodMissing(String name, Object args) {
        this
    }

    void set(Object value) { this.value = value }
    void from(Object value) { this.value = value }
    void convention(Object value) { if (this.value == null) this.value = value }
    Object dir(Object value) { this.value = value; this }
    Object get() { value }
}
'''.stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/xml/Tasks.groovy').text = '''
package org.flowdigger.gradle.xml

import org.flowdigger.stub.DynamicStubTask

class XsltTask extends DynamicStubTask { }
class SchematronTask extends DynamicStubTask { }
class XSpecTask extends DynamicStubTask { }
'''.stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/ooxml/Tasks.groovy').text = '''
package org.flowdigger.gradle.ooxml

import org.flowdigger.stub.DynamicStubTask

class OoXmlToCanonicalTask extends DynamicStubTask { }
'''.stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/python/Tasks.groovy').text = '''
package org.flowdigger.gradle.python

import org.flowdigger.stub.DynamicStubTask

class PythonRunnerTask extends DynamicStubTask { }
'''.stripIndent()

new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/antlr/Tasks.groovy').text = '''
package org.flowdigger.gradle.antlr

import org.flowdigger.stub.DynamicStubTask

class XmlAstJavaGradleTask extends DynamicStubTask { }
class XmlAstPlsqlGradleTask extends DynamicStubTask { }
'''.stripIndent()
    }
}
