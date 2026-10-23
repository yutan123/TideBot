from pathlib import Path
root=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
p=root/'android/app/src/main/kotlin/com/yutan123/tidebot/TideBackgroundService.kt'
s=p.read_text()
s=s.replace('        private const val TAG = "TideBackgroundService"','''        private val requestLeases = TideRequestLeases { android.os.SystemClock.elapsedRealtime() }
        @Volatile private var running: TideBackgroundService? = null
        private const val ACTION_PROTECT_REQUEST = "com.yutan123.tidebot.PROTECT_REQUEST"
        fun beginRequest(context: Context, id: String) {
            requestLeases.begin(id)
            try {
                val intent = Intent(context, TideBackgroundService::class.java).setAction(ACTION_PROTECT_REQUEST)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                requestLeases.end(id)
                throw error
            }
        }
        fun renewRequest(id: String) { requestLeases.renew(id) }
        fun endRequest(id: String) {
            requestLeases.end(id)
            running?.stopIfIdle()
        }
        private const val TAG = "TideBackgroundService"''')
s=s.replace('''        acquireWakeLock()
    }
    override fun onStartCommand''','''        running = this
        acquireWakeLock()
        serviceScope.launch {
            while (isActive) {
                delay(60_000)
                withContext(Dispatchers.Main.immediate) {
                    if (activeTasks.get() > 0 || requestLeases.hasActive()) acquireWakeLock()
                    stopIfIdle()
                }
            }
        }
    }
    override fun onStartCommand''',1)
s=s.replace('''        when (intent?.action) {
            ACTION_EXECUTE_TASK''','''        when (intent?.action) {
            ACTION_PROTECT_REQUEST -> {
                updateNotification("正在接收回复，可切换到后台")
                stopIfIdle()
            }
            ACTION_EXECUTE_TASK''')
s=s.replace('if (activeTasks.get() <= 0) {','if (activeTasks.get() <= 0 && !requestLeases.hasActive()) {')
s=s.replace('''        serviceScope.cancel()
        releaseWakeLock()''','''        if (running === this) running = null
        serviceScope.cancel()
        releaseWakeLock()''')
p.write_text(s)
p=root/'android/app/src/main/kotlin/com/yutan123/tidebot/MainActivity.kt'
s=p.read_text().replace('    private var nativeChannel: MethodChannel? = null','''    private var nativeChannel: MethodChannel? = null
    private val requestExecutionIds = mutableSetOf<String>()''')
s=s.replace('        backgroundCoordinator.shutdown()','''        requestExecutionIds.forEach { TideBackgroundService.endRequest(it) }
        requestExecutionIds.clear()
        backgroundCoordinator.shutdown()''',1)
s=s.replace('            when (call.method) {','''            when (call.method) {
                "beginRequestExecution" -> {
                    val id = call.argument<String>("id").orEmpty()
                    try {
                        require(id.isNotBlank())
                        TideBackgroundService.beginRequest(applicationContext, id)
                        requestExecutionIds.add(id)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("REQUEST_PROTECTION_FAILED", error.javaClass.simpleName, null)
                    }
                }
                "renewRequestExecution" -> {
                    val id = call.argument<String>("id").orEmpty()
                    if (id in requestExecutionIds) TideBackgroundService.renewRequest(id)
                    result.success(null)
                }
                "endRequestExecution" -> {
                    val id = call.argument<String>("id").orEmpty()
                    if (requestExecutionIds.remove(id)) TideBackgroundService.endRequest(id)
                    result.success(null)
                }''',1)
p.write_text(s)
