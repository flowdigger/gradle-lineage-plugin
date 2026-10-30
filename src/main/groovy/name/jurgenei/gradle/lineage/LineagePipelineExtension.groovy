package name.jurgenei.gradle.lineage

class LineagePipelineExtension {
    String sourceRoot
    String lineageBuildRoot
    Boolean skipLineageValidations
    List<String> schemaNames = []
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
    final MutableProperty<String> ref = new MutableProperty<>()
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
    final MutableListProperty<String> includes = new MutableListProperty<>()
    final MutableListProperty<String> schemas = new MutableListProperty<>()

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

class MutableListProperty<T> {
    private List<T> value = []

    void set(List<?> value) {
        this.value = (value ?: []).collect { it as T }
    }

    void set(T... values) {
        this.value = values ? values.toList() : []
    }

    List<T> get() {
        return value
    }
}
