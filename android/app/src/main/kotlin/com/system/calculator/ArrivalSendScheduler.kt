package com.system.calculator

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.UNIQUE_NAME_KEY
import java.util.concurrent.TimeUnit

/**
 * Asks the Workmanager plugin to run the Dart task [TASK] in a headless isolate.
 * Dart reads [ArrivalQueue] and sends the arrival messages, so no chat code is
 * needed here. The plugin must have been initialised once from Dart (done at app start).
 */
object ArrivalSendScheduler {
    const val TASK = "arrival_send"
    private const val DART_TASK_KEY = "dev.fluttercommunity.workmanager.DART_TASK"

    fun enqueue(context: Context) {
        val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
            .setInputData(workDataOf(DART_TASK_KEY to TASK, UNIQUE_NAME_KEY to TASK))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(TASK, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }
}
