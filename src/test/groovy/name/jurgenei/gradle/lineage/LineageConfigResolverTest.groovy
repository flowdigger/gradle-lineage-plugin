package name.jurgenei.gradle.lineage

import org.gradle.testfixtures.ProjectBuilder
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

import static org.junit.jupiter.api.Assertions.assertEquals

class LineageConfigResolverTest {
    @TempDir
    File tempDir

    @Test
    void "uses sourceSet schemas over derived and fallback values"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()
        def repoDir = new File(tempDir, 'demo-lineage')
        new File(repoDir, 'sql/buss').mkdirs()
        new File(repoDir, 'sql/cons').mkdirs()

        def ext = baseExtension(tempDir)
        ext.schemaNames = ['legacy_a', 'legacy_b']
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('sql') {
                parserPlugin.set('name.jurgenei.gradle.antlr.plsql')
                sourceDirectory.set('sql')
                schemas.set('SDP', 'DSA')
                includes.set(['**/*.sql'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals(['sdp', 'dsa'], cfg.schemaNames)
        assertEquals(['sdp', 'dsa'], cfg.sqlSourceSets[0].sqlSchemaNames)
    }

    @Test
    void "derives schemas from source directory folders when sourceSet schemas not configured"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()
        def repoDir = new File(tempDir, 'demo-lineage')
        new File(repoDir, 'sql/buss').mkdirs()
        new File(repoDir, 'sql/cons').mkdirs()
        new File(repoDir, 'sql/root-level.sql').text = 'select 1 from dual;'

        def ext = baseExtension(tempDir)
        ext.schemaNames = ['legacy_a']
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('sql') {
                parserPlugin.set('name.jurgenei.gradle.antlr.plsql')
                sourceDirectory.set('sql')
                includes.set(['**/*.sql'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals(['buss', 'cons'], cfg.schemaNames)
        assertEquals(['buss', 'cons'], cfg.sqlSourceSets[0].sqlSchemaNames)
    }

    @Test
    void "falls back to lineagePipeline schemaNames when source directory not available yet"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()

        def ext = baseExtension(tempDir)
        ext.schemaNames = ['buss', 'cons']
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('sql') {
                parserPlugin.set('name.jurgenei.gradle.antlr.plsql')
                sourceDirectory.set('sql')
                includes.set(['**/*.sql'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals(['buss', 'cons'], cfg.schemaNames)
        assertEquals(['buss', 'cons'], cfg.sqlSourceSets[0].sqlSchemaNames)
    }

    @Test
    void "drops empty schema names from schema fan-out list"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()
        def repoDir = new File(tempDir, 'demo-lineage')
        new File(repoDir, 'sql/buss').mkdirs()
        new File(repoDir, 'sql/root-level.sql').text = 'select 1 from dual;'

        def ext = baseExtension(tempDir)
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('sql') {
                parserPlugin.set('name.jurgenei.gradle.antlr.plsql')
                sourceDirectory.set('sql')
                schemas.set('', 'buss')
                includes.set(['**/*.sql'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals(['buss'], cfg.schemaNames)
        assertEquals(['buss'], cfg.sqlSourceSets[0].sqlSchemaNames)
    }

    @Test
    void "uses fallback repo ref when ref is not set"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()

        def ext = baseExtension(tempDir)
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('java') {
                parserPlugin.set('name.jurgenei.gradle.antlr.java')
                sourceDirectory.set('src/main/java')
                includes.set(['**/*.java'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals('main', cfg.repos[0].ref)
        assertEquals('fallback', cfg.repos[0].refSource)
    }

    @Test
    void "uses lineageRepoRef override when ref is not set"() {
        def project = ProjectBuilder.builder().withProjectDir(tempDir).build()
        project.extensions.extraProperties.set('lineageRepoRef', 'release-branch')

        def ext = baseExtension(tempDir)
        ext.repos.repo {
            uri.set('https://github.com/example/demo-lineage.git')
            sourceSet('java') {
                parserPlugin.set('name.jurgenei.gradle.antlr.java')
                sourceDirectory.set('src/main/java')
                includes.set(['**/*.java'])
            }
        }

        def cfg = LineageConfigResolver.resolve(project, ext)
        assertEquals('release-branch', cfg.repos[0].ref)
        assertEquals('lineageRepoRef/LINEAGE_REPO_REF override', cfg.repos[0].refSource)
    }

    private static LineagePipelineExtension baseExtension(File sourceRoot) {
        def ext = new LineagePipelineExtension()
        ext.sourceRoot = sourceRoot.absolutePath
        ext.lineageBuildRoot = new File(sourceRoot, 'build/lineage').absolutePath
        ext
    }
}
