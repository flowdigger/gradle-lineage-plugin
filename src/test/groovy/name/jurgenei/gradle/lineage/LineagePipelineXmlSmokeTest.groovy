package name.jurgenei.gradle.lineage

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

import static org.gradle.testkit.runner.TaskOutcome.SUCCESS
import static org.junit.jupiter.api.Assertions.assertEquals

class LineagePipelineXmlSmokeTest {
    private static final String XML_PLUGIN_VERSION = '0.1.15'

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
        GradleRunner.create()
                .withProjectDir(projectDir)
                .withPluginClasspath()
                .forwardOutput()
    }

    private static void writeSettings(File projectDir) {
        new File(projectDir, 'settings.gradle').text = """
rootProject.name = 'lineage-xml-smoke'
""".stripIndent()
    }

    private static void writeXspecBuild(File projectDir) {
        def pluginRoot = new File(System.getProperty('user.dir'))
        new File(projectDir, 'build.gradle').text = """
plugins {
  id 'name.jurgenei.gradle.xml' version '${XML_PLUGIN_VERSION}'
}

tasks.register('runXSpecSmoke', name.jurgenei.gradle.xml.XSpecTask) {
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
  id 'name.jurgenei.gradle.xml' version '${XML_PLUGIN_VERSION}'
}

tasks.register('runSchematronSmoke', name.jurgenei.gradle.xml.SchematronTask) {
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
}
