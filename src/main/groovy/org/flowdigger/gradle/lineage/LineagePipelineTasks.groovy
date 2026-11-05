package org.flowdigger.gradle.lineage

import org.gradle.api.Project

import org.flowdigger.gradle.lineage.pipeline.step1.Step1ParseTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step2.Step2ObserveTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step3.Step3DirectFlowTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step4.Step4ValidateDirectFlowTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step5.Step5MergeTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step6.Step6StitchTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step7.Step7ValidateLineageTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step8.Step8ExportTasksRegistrar
import org.flowdigger.gradle.lineage.pipeline.step9.Step9PublishTasksRegistrar

class LineagePipelineTasks {
    static void register(Project project, Map<String, Object> cfg, LineagePipelineExtension ext) {
        def ctx = LineagePipelineContext.create(project, cfg, ext)
        Step1ParseTasksRegistrar.register(ctx)
        Step2ObserveTasksRegistrar.register(ctx)
        Step3DirectFlowTasksRegistrar.register(ctx)
        Step4ValidateDirectFlowTasksRegistrar.register(ctx)
        Step5MergeTasksRegistrar.register(ctx)
        Step6StitchTasksRegistrar.register(ctx)
        Step7ValidateLineageTasksRegistrar.register(ctx)
        Step8ExportTasksRegistrar.register(ctx)
        Step9PublishTasksRegistrar.register(ctx)
    }
}
