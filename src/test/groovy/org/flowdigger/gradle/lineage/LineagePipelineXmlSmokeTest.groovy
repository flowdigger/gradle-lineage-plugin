package org.flowdigger.gradle.lineage

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

import static org.gradle.testkit.runner.TaskOutcome.SUCCESS
import static org.junit.jupiter.api.Assertions.assertEquals

class LineagePipelineXmlSmokeTest {
    @TempDir
    File testProjectDir

    @Test
    void "xspec smoke test for representative pipeline stylesheet"() {
        writeSettings(testProjectDir)
        writeXspecBuild(testProjectDir)
        writeXspecFixture(testProjectDir)

        def result = runner(testProjectDir)
                .withArguments('runXSpecSmoke')
                .build()

        assertEquals(SUCCESS, result.task(':runXSpecSmoke').outcome)
    }

    @Test
    void "schematron smoke test for representative pipeline schema"() {
        writeSettings(testProjectDir)
        writeSchematronBuild(testProjectDir)
        writeSchematronFixture(testProjectDir)

        def result = runner(testProjectDir)
                .withArguments('runSchematronSmoke')
                .build()

        assertEquals(SUCCESS, result.task(':runSchematronSmoke').outcome)
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

    private static void writeSettings(File projectDir) {
        writeStubXmlPlugin(projectDir)
        new File(projectDir, 'settings.gradle').text = """
rootProject.name = 'lineage-xml-smoke'
""".stripIndent()
    }

    private static void writeXspecBuild(File projectDir) {
        def pluginRoot = new File(System.getProperty('user.dir'))
        new File(projectDir, 'build.gradle').text = """
plugins {
  id 'org.flowdigger.xml'
}

tasks.register('runXSpecSmoke', org.flowdigger.gradle.xml.XSpecTask) {
  source fileTree('src/main/xspec') { include '**/*.xspec' }
  outputDir.set(layout.buildDirectory.dir('reports/xspec'))
}

ext.pipelineRoot = '${new File(pluginRoot, 'pipeline').absolutePath.replace('\\', '\\\\')}'
""".stripIndent()
    }

    private static void writeXspecFixture(File projectDir) {
        def xspecDir = new File(projectDir, 'src/main/xspec')
        xspecDir.mkdirs()
        new File(xspecDir, 'identity-smoke.xspec').text = """
<x:description xmlns:x="http://www.jenitennison.com/xslt/xspec"
               stylesheet="${new File(System.getProperty('user.dir'), 'pipeline/6.stitch/src/main/xsl/identity.xsl').absolutePath.replace('\\', '/')}">
  <x:scenario label="identity stylesheet smoke">
    <x:context><root><node/></root></x:context>
    <x:expect label="xspec invocation completes" test="true()"/>
  </x:scenario>
</x:description>
""".trim()
    }

    private static void writeSchematronBuild(File projectDir) {
        new File(projectDir, 'build.gradle').text = """
plugins {
  id 'org.flowdigger.xml'
}

tasks.register('runSchematronSmoke', org.flowdigger.gradle.xml.SchematronTask) {
  schema '${new File(System.getProperty('user.dir'), 'pipeline/7.validate-lineage/src/main/schematron/validate-lineage.sch').absolutePath.replace('\\', '\\\\')}'
  source file('src/main/xml/sample.xml')
  outputDir.set(layout.buildDirectory.dir('reports/schematron'))
  failOnError.set(false)
  expandText.set(true)
}
""".stripIndent()
    }

    private static void writeSchematronFixture(File projectDir) {
        def xmlDir = new File(projectDir, 'src/main/xml')
        xmlDir.mkdirs()
        new File(xmlDir, 'sample.xml').text = """
<stitched-lineage>
  <stitched-flow direct-flow-id="df-1"/>
  <stitch-link from-direct-flow-id="df-1" to-direct-flow-id="df-1"/>
</stitched-lineage>
""".trim()
    }

    private static void writeStubXmlPlugin(File projectDir) {
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
  }
}
""".stripIndent()

        new File(buildSrcDir, 'src/main/groovy/org/flowdigger/stub').mkdirs()
        new File(buildSrcDir, 'src/main/groovy/org/flowdigger/gradle/xml').mkdirs()

        new File(buildSrcDir, 'src/main/groovy/org/flowdigger/stub/NoopXmlPlugin.groovy').text = '''
package org.flowdigger.stub

import org.gradle.api.Plugin
import org.gradle.api.Project

class NoopXmlPlugin implements Plugin<Project> {
    void apply(Project project) { }
}
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
    }
}
