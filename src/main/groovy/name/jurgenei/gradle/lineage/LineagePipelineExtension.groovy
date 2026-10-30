package name.jurgenei.gradle.lineage

class LineagePipelineExtension {
    String sourceRoot
    String lineageBuildRoot
    Boolean skipLineageValidations
    List<String> schemaNames = ['buss', 'cons', 'sdp', 'dsa', 'sdp_staging', 'dsa_staging']
    String architectureModelFile
    String architectureProcessedFile
    String appSticherStylesheet

    final ReposConfig repos = new ReposConfig()

    void repos(Closure<?> closure) {
        closure.delegate = repos
        closure.resolveStrategy = Closure.DELEGATE_FIRST
        closure.call()
    }
}

class ReposConfig {
    final List<RepoConfig> items = []

    void repo(Closure<?> closure) {
        def repo = new RepoConfig()
        closure.delegate = repo
        closure.resolveStrategy = Closure.DELEGATE_FIRST
        closure.call()
        items << repo
    }
}

class RepoConfig {
    final MutableProperty<String> uri = new MutableProperty<>()
    final MutableProperty<String> ref = new MutableProperty<>("master")
    final List<SourceSetConfig> sourceSets = []

    void sourceSet(String name, Closure<?> closure) {
        def sourceSet = new SourceSetConfig(name)
        closure.delegate = sourceSet
        closure.resolveStrategy = Closure.DELEGATE_FIRST
        closure.call()
        sourceSets << sourceSet
    }
}

class SourceSetConfig {
    final String name
    final MutableProperty<String> parserPlugin = new MutableProperty<>()
    final MutableProperty<Object> sourceDirectory = new MutableProperty<>()
    final MutableProperty<List<String>> includes = new MutableProperty<>([])

    SourceSetConfig(String name) {
        this.name = name
    }
}

class MutableProperty<T> {
    private T value

    MutableProperty() {}

    MutableProperty(T defaultValue) {
        this.value = defaultValue
    }

    void set(T value) {
        this.value = value
    }

    T get() {
        return value
    }
}
