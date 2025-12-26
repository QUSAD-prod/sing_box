package com.qusadprod.sing_box.ktx

import kotlin.coroutines.Continuation

/**
 * Utilities for working with Continuation
 * Copied and adapted from sing-box-for-android
 */
fun <T> Continuation<T>.tryResume(value: T) {
    try {
        resumeWith(Result.success(value))
    } catch (ignored: IllegalStateException) {
    }
}

fun <T> Continuation<T>.tryResumeWithException(exception: Throwable) {
    try {
        resumeWith(Result.failure(exception))
    } catch (ignored: IllegalStateException) {
    }
}

