package org.flowdigger.gradle.lineage

class LineageTaskNames {
    static String toTaskSuffix(String key) {
        key.split(/[^A-Za-z0-9]+/)
                .findAll { !it.isBlank() }
                .collect { it.capitalize() }
                .join('')
    }
}
