from pathlib import Path
root=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
k=root/'android/app/src/main/kotlin/com/yutan123/tidebot'
p=k/'TideBackgroundService.kt'; s=p.read_text()
s=s.replace('''        @Volatile private var running: TideBackgroundService? = null''','''        @Volatile private var running: TideBackgroundService? = null
        private val handoffLocks = mutableListOf<PowerManager.WakeLock>()
        private fun releaseHandoffs() = synchronized(handoffLocks) {
            handoffLocks.forEach { if (it.isHeld) it.release() }
            handoffLocks.clear()
        }''',1)
s=s.replace('''        fun startTask(context: Context, taskId: String, scheduledTime: Long) {
            val intent''','''        fun startTask(context: Context, taskId: String, scheduledTime: Long) {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val handoff = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TideBot:ServiceHandoff")
                .apply { setReferenceCounted(false); acquire(15_000L) }
            synchronized(handoffLocks) { handoffLocks.add(handoff) }
            val intent''',1)
start=s.index('        fun startTask('); a=s.index('            if (Build.VERSION.SDK_INT',start); b=s.index('\n        }',a)
s=s[:a]+'''            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                synchronized(handoffLocks) {
                    handoffLocks.remove(handoff)
                    if (handoff.isHeld) handoff.release()
                }
                throw error
            }'''+s[b:]
s=s.replace('''        latestStartId = startId
        acquireWakeLock()''','''        latestStartId = startId
        acquireWakeLock()
        releaseHandoffs()''',1)
p.write_text(s)
p=k/'TideTaskWork.kt'; s=p.read_text().replace('fun enqueue(context: Context, taskId: String, scheduledTime: Long) {','fun enqueue(context: Context, taskId: String, scheduledTime: Long): Operation {').replace('''            WorkManager.getInstance(context).enqueueUniqueWork(''','''            return WorkManager.getInstance(context).enqueueUniqueWork(''',1); p.write_text(s)
p=k/'TideAlarmReceiver.kt'; s=p.read_text().replace('''                    TideTaskWork.enqueue(context, taskId, scheduledTime)''','''                    TideTaskWork.enqueue(context, taskId, scheduledTime).result
                        .get(5, java.util.concurrent.TimeUnit.SECONDS)''',1); p.write_text(s)
# Whitespace cleanup on touched Kotlin files.
for p in k.glob('*.kt'):
    if p.name in {'TideBackgroundLog.kt','TideTaskExecutor.kt','TideProactiveTasks.kt'}:
        p.write_text(p.read_text().rstrip()+'\n')