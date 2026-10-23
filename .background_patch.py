from pathlib import Path
root=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
k=root/'android/app/src/main/kotlin/com/yutan123/tidebot'
p=k/'TideBackgroundService.kt'; s=p.read_text(); needle='        startForeground(NOTIFICATION_ID, buildNotification("初始化中..."))\n'; assert needle in s
s=s.replace(needle,needle+'''        running = this
        serviceScope.launch {
            while (isActive) {
                delay(60_000)
                withContext(Dispatchers.Main.immediate) {
                    if (activeTasks.get() > 0 || requestLeases.hasActive()) acquireWakeLock()
                    stopIfIdle()
                }
            }
        }
''',1); p.write_text(s)
p=k/'MainActivity.kt'; s=p.read_text(); needle='''        TideNativeNotifications.activityVisible = false
'''; assert needle in s
s=s.replace(needle,needle+'''        // Persist deadlines natively before Flutter's UI timers can be suspended.
        backgroundCoordinator.execute {
            runCatching {
                TideFutureTasks.reconcile(applicationContext)
                TideProactiveTasks.reconcile(applicationContext)
                TideEnhancedBackgroundWork.ensureScheduled(applicationContext)
                TideMasterScheduler.restoreAllTasks(applicationContext)
            }.onFailure { android.util.Log.e("TideBackground", "Background handoff failed", it) }
        }
''',1); p.write_text(s)
p=root/'lib/native_background_coordinator.dart'; s=p.read_text().replace('        await Future<void>.delayed(const Duration(milliseconds: 200));\n',''); p.write_text(s)
p=root/'lib/request_execution_lease.dart'; s=p.read_text().replace("import 'dart:async';", "import 'dart:async';\nimport 'native_background_coordinator.dart';")
s=s.replace('''    _renewal?.cancel();''','''    // Complete native deadline registration while request protection is still held.
    await NativeBackgroundCoordinator.synchronize();
    _renewal?.cancel();''',1); p.write_text(s)
p=k/'TideTaskWork.kt'; s=p.read_text(); needle='''            setForeground(ForegroundInfo(998, TideNativeNotifications.workNotification(applicationContext),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))'''; assert needle in s
s=s.replace(needle,'''            try {
                setForeground(ForegroundInfo(998, TideNativeNotifications.workNotification(applicationContext),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))
            } catch (error: CancellationException) {
                throw error
            } catch (error: IllegalStateException) {
                // Android 12+/15 can reject FGS starts/quotas. A regular Worker
                // still has a wakelock and a 10-minute window for this 5-minute request.
                Log.w("TideTaskWork", "Foreground promotion unavailable; using Worker execution", error)
            }'''); p.write_text(s)
p=k/'TideEnhancedBackgroundWork.kt'; s=p.read_text(); needle='''                setForeground(ForegroundInfo(998, TideNativeNotifications.workNotification(applicationContext), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))'''; assert needle in s
s=s.replace(needle,'''                try {
                    setForeground(ForegroundInfo(998, TideNativeNotifications.workNotification(applicationContext), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))
                } catch (error: kotlinx.coroutines.CancellationException) {
                    throw error
                } catch (error: IllegalStateException) {
                    Log.w(TAG, "Foreground promotion unavailable; using Worker execution", error)
                }'''); p.write_text(s)
# Guard the broadcast-to-service handoff against device sleep before onCreate acquires its lock.
p=k/'TideAlarmReceiver.kt'; s=p.read_text(); s=s.replace('''        val pending = goAsync()
''','''        val pending = goAsync()
        val power = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val handoff = power.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "TideBot:AlarmHandoff")
            .apply { setReferenceCounted(false); acquire(15_000L) }
''',1)
s=s.replace('''                pending.finish()''','''                if (handoff.isHeld) handoff.release()
                pending.finish()'''); p.write_text(s)