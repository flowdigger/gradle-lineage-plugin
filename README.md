# Gradle Lineage Plugin (`name.jurgenei.gradle.lineage`)

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

Default output root:

```text
../../../build/lineage-uniform
```

Override per run:

```bash
./gradlew -PlineageBuildRoot=/tmp/lineage-uniform build
```

---

## Apply plugin

```groovy
plugins {
  id 'base'
  id 'name.jurgenei.gradle.lineage'
}
```

---

## Configure `lineagePipeline`

Minimal example:

```groovy


lineagePipeline {
  sourceRoot = rootProject.projectDir.parentFile.absolutePath
  lineageBuildRoot = rootProject.file('build/lineage').absolutePath
  architectureModelFile = "${sourceRoot}/src/test/archimate-model.xml"

  repos {
    repo {
      uri.set("https://github.com/jurgenei/gradle-lineage-plugin")
      ref.set("main")
      sourceSet('sql') {
        parserPlugin.set("name.jurgenei.gradle.antlr.plsql")
        sourceDirectory.set(file('src/test/sql'))
        includes.set(["**/*.sql"])
      }
      sourceSet('java') {
        parserPlugin.set("name.jurgenei.gradle.antlr.java")
        sourceDirectory.set(file('src/test/java'))
        includes.set(["**/*.java"])
      }
    }
  }

  // Optional:
  // architectureProcessedFile defaults to:
  // "${lineageBuildRoot}/6.stitch/architecture/<architectureModelFile basename>"
  //
  // appSticherStylesheet defaults to bundled plugin stylesheet:
  // "<plugin pipeline root>/6.stitch/src/main/xsl/call-app.xsl"
  // Override when setup needs custom stitching logic:
  // appSticherStylesheet = rootProject.file('lineage/call-app.custom.xsl').absolutePath
}
```

`syncLineageRepos` clones/updates configured repositories under `sourceRoot` before parse tasks. For existing checkouts, it fetches remotes before checking out configured `ref`; fast-forward pull still requires `-PlineageSyncUpdate=true` (or `LINEAGE_SYNC_UPDATE=true`).

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
build-logic/src/main/groovy/name/jurgenei/lineage/LineageConventionsPlugin.groovy
```