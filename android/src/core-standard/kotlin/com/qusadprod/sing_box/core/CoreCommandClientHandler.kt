package com.qusadprod.sing_box.core

import io.nekohasekai.libbox.CommandClientHandler

/**
 * The [CommandClientHandler] members that differ between the cores; Gradle compiles
 * `src/core-<core>/kotlin` of the linked core (`src/core-lx` for sing-box-lx). The standard
 * libbox has none.
 */
internal abstract class CoreCommandClientHandler : CommandClientHandler
