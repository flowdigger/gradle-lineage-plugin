# Gradle Lineage Plugin (`org.flowdigger.gradle.lineage`)

![Conformance](https://img.shields.io/badge/Conformance-Check--All%20Passing-brightgreen)

[![Plugin Portal](https://img.shields.io/gradle-plugin-portal/v/org.flowdigger.gradle.lineage?label=Plugin%20Portal)](https://plugins.gradle.org/plugin/org.flowdigger.gradle.lineage)
[![Build and Test](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/gradle-build.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/gradle-build.yml)
[![JUnit Report](https://img.shields.io/badge/JUnit-Report-blue?logo=githubactions)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/gradle-build.yml)
[![Coverage CI](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/coverage.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/coverage.yml)
[![CodeQL](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/codeql.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/codeql.yml)
[![Dependency Check](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/dependency-check.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/dependency-check.yml)
[![SpotBugs Security](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/spotbugs-security.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/spotbugs-security.yml)
[![Checkstyle](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/checkstyle.yml/badge.svg)](https://github.com/jurgenei/gradle-lineage-plugin/actions/workflows/checkstyle.yml)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-025E8C?logo=dependabot)](https://github.com/jurgenei/gradle-lineage-plugin/security/dependabot)
[![Coverage](https://codecov.io/gh/jurgenei/gradle-lineage-plugin/graph/badge.svg?branch=main)](https://codecov.io/gh/jurgenei/gradle-lineage-plugin)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Java](https://img.shields.io/badge/java-21+-green.svg)](https://www.oracle.com/java/)
[![Gradle](https://img.shields.io/badge/gradle-9.5+-blue.svg)](https://gradle.org/)

Canonical lineage pipeline plugin for SQL + Java repositories.

Pipeline contract:

```text
SOURCE -> SYNTAX -> SEMANTICS -> FLOW -> LINEAGE
```

Implemented as numbered phases:

```text
1.parse
2.observe
3.direct-flow
4.validate-direct-flow
5.merge
6.stitch
7.validate-lineage
8.export
9.publish
```

---

## What plugin does

Plugin wires deterministic lifecycle that:

1. parses SQL/Java sources
2. extracts semantic observations
3. derives direct flows
4. validates direct-flow contracts
5. merges and prepares stitch inputs
6. stitches canonical lineage
7. validates stitched lineage
8. exports GraphML/RDF/JSON (+ graph layout)
9. publishes artifacts

Internal wiring now split by responsibility:
- `LineageConventionsPlugin`: root-only apply + orchestration
- `LineageConfigResolver`: extension + property/env resolution and source-set validation
- `LineageRepoSyncTasks`: `syncLineageRepo*` and `syncLineageRepos`
- `LineagePipelineTasks`: phase orchestration only
- `LineagePipelineContext`: shared resolved phase context
- `pipeline/{1.parse..9.publish}`: multi-project phase modules, each with own `build.gradle` + `src/main` resources and registrar code
- `LineageGlobalTasks`: `clean`, `cleanAllLineage`, and `build -> publishLineage`

Sanity coverage:
- Gradle TestKit task-graph and clean-behavior tests
- XML smoke tests using `gradle-xml-plugin` XSpec/Schematron tasks for representative pipeline assets

---

## Configure `lineagePipeline`

Minimal example:

```groovy

plugins {
  id 'base'
  id 'org.flowdigger.gradle.lineage' version '0.1.0'
  id 'org.flowdigger.gradle.xml' version '0.1.15'
  id 'org.flowdigger.gradle.antlr.plsql' version '0.1.8'
  id 'org.flowdigger.gradle.antlr.java' version '0.1.4'
  id 'org.flowdigger.gradle.ooxml' version '0.1.12' apply false
  id 'org.flowdigger.gradle.python' version '0.1.4' apply false
}

repositories {
  gradlePluginPortal()
  mavenCentral()
}

def gSampleSourceRoot = rootProject.file('build/source').absolutePath
def gSampleLineageBuildRoot = rootProject.file('build/lineage').absolutePath
def gSampleArchitectureModelFile = rootProject.file('src/main/xml/architecture.xml').absolutePath

println("Sample lineage build root: ${gSampleLineageBuildRoot}")
println("Sample source root: ${gSampleSourceRoot}")
println("Sample architecture model file: ${gSampleArchitectureModelFile}")

lineagePipeline {
  sourceRoot = gSampleSourceRoot
  lineageBuildRoot = gSampleLineageBuildRoot
  architectureModelFile = gSampleArchitectureModelFile
  skipLineageValidations = true

  repos {
    repo {
      uri.set("https://github.com/jurgenei/gradle-lineage-plugin")
      sourceSet('sql-sample') {
        parserPlugin.set("org.flowdigger.gradle.antlr.plsql")
        sourceDirectory.set(file('samples/java-plsql/src/main/sql'))
        schemas.set(['dsa'])
        includes.set(["**/*.sql"])
      }
      sourceSet('java-sample') {
        parserPlugin.set("org.flowdigger.gradle.antlr.java")
        sourceDirectory.set(file('samples/java-plsql/src/main/java'))
        includes.set(["**/*.java"])
      }
    }
  }
}
```

SQL schema resolution precedence for merge/index fan-out:
1. `sourceSet.schemas(...)` when configured
2. top-level folders under SQL `sourceDirectory` (for example `buss/**/*.sql`, `cons/**/*.sql`)
3. fallback `lineagePipeline.schemaNames` (compatibility, including first run before repo sync)

Root-level SQL files directly under `sourceDirectory` map to default schema `""` and are still parsed/observed, but schema-index tasks are generated only for non-empty schema names.

`syncLineageRepos` clones/updates configured repositories under `sourceRoot` before parse tasks. For existing checkouts, it fetches remotes, checks out configured `ref`, then runs fast-forward `git pull` from remote.

When `ref.set(...)` is omitted, lineage repo `ref` is resolved with precedence:
1. `-PlineageRepoRef=<ref>` (or legacy `-PlineageSampleRef=<ref>`)
2. `LINEAGE_REPO_REF` (or legacy `LINEAGE_SAMPLE_REF`)
3. current git branch (`git rev-parse --abbrev-ref HEAD`)
4. fallback `main`

During `syncLineageRepo*` tasks, plugin logs selected branch source in lifecycle output.

---

## Lifecycle tasks

Run phase chain tasks from root project:

```bash
./gradlew parseLineageSources
./gradlew extractLineageObservations
./gradlew deriveDirectFlows
./gradlew validateDirectFlows
./gradlew mergeDirectFlows
./gradlew stitchLineage
./gradlew validateLineage
./gradlew exportGraphML
./gradlew exportRDF
./gradlew exportLineageArtifacts
./gradlew publishLineage
```

Full pipeline:

```bash
./gradlew build
```

Task graph only:

```bash
./gradlew -m publishLineage
```

Publish plugin to Gradle Plugin Portal:

```bash
./gradlew publishToPluginPortal \
  -Pgradle.publish.key=<key> \
  -Pgradle.publish.secret=<secret>
```

Skip validation guards (local diagnostics only):

```bash
./gradlew publishLineage -PskipLineageValidations=true
```

or

```bash
SKIP_LINEAGE_VALIDATIONS=true ./gradlew publishLineage
```

---

## Phase contracts

| Phase | Main objective | Key outputs |
|---|---|---|
| `1.parse` | Parse syntax only | `1.parse/sql/ast`, `1.parse/java/*/ast` |
| `2.observe` | Extract semantic observations | `2.observe/{sql,java,configuration,ooxml}` |
| `3.direct-flow` | Derive immediate `source -> operation -> target` flow | `3.direct-flow/{sql,java}` |
| `4.validate-direct-flow` | Schematron validation (fail-fast) | `4.validate-direct-flow/direct-flows.xml` + reports |
| `5.merge` | Merge validated flows; generate SQL index contract | `5.merge/direct-flows.merged.xml`, `5.merge/sql-index/*` |
| `6.stitch` | Build canonical stitched lineage | `6.stitch/stitched-lineage.xml` + app glue artifacts |
| `7.validate-lineage` | Validate stitched lineage | `7.validate-lineage/*` |
| `8.export` | Produce projections + layout | `8.export/{graphml,rdf,json,graph}` + app projections |
| `9.publish` | Package final artifacts | `9.publish/artifacts` |

---

## SQL + Java contract

- Canonical direct-flow and stitched lineage include SQL and Java flows:
  - `4.validate-direct-flow/direct-flows.xml`
  - `5.merge/direct-flows.merged.xml`
  - `6.stitch/stitched-lineage.xml`
- `call-app.xsl` consumes SQL index contract from `5.merge/sql-index`:
  - `call-tree.{schema}.xir`
  - `procedure.{schema}.xir`
  - `table-index.{schema}.xir`
- Java lineage currently models class-to-class flow (`invokes`, `instantiates`), not field-level lineage.
- Per-processor app outputs are exported from `lineage/app/xir` during `8.export`.

---

## Clean behavior

```bash
./gradlew clean
```

Removes `2.observe` through `9.publish` and keeps `1.parse` (expensive parse cache).

Full wipe including parse:

```bash
./gradlew cleanAllLineage
```

---

## Troubleshooting

**Missing SQL index files during `generateApps`**  
Run:

```bash
./gradlew buildSqlIndicesForStitch
```

Check:

```text
build/lineage-uniform/5.merge/sql-index
```

**Observe phase fails on docs/config inputs**  
- `docs/active` and `docs/fd` OOXML observe tasks now auto-skip when folders are missing or contain no OOXML files.
- `configuration` inputs are still expected when `generateConfiguration` runs.

**Long parse times / memory pressure**  
Tune parser concurrency in conventions plugin:

```text
build-logic/src/main/groovy/org/flowdigger/lineage/LineageConventionsPlugin.groovy
```