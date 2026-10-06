package com.v4n1lla.diligent_life

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.hardware.*
import android.os.*
import android.provider.Settings
import java.time.Instant
import java.time.ZoneId

class StepTrackingService : Service(), SensorEventListener2 {
    private lateinit var sensors: SensorManager
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private var db: SQLiteDatabase? = null
    private var cursor: StepCursor? = null
    private val pending = linkedMapOf<String, Triple<Long, String, Long>>()
    private var scheduled = false
    private val flushTask = Runnable { scheduled = false; persist() }
    private var boot = 0
    private var suspended = false
    @Volatile private var destroyed = false
    private val flushResults = mutableListOf<(Boolean) -> Unit>()
    private val flushTimeout = Runnable { completeFlush() }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("daily_steps", "일상 걸음 기록", NotificationManager.IMPORTANCE_LOW))
        val intent = PendingIntent.getActivity(this, 140, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "daily_steps") else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("Diligent Life 만보기")
            .setContentText("일상 걸음을 기록하고 있어요 · 설정에서 끌 수 있어요")
            .setContentIntent(intent).setOngoing(true).setOnlyAlertOnce(true).build()
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(140, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            else startForeground(140, notification)
            worker = HandlerThread("DiligentSteps").apply { start() }
            handler = Handler(worker.looper)
            sensors = getSystemService(SensorManager::class.java)
            val sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            if (sensor == null || !allowed(this)) { stopSelf(); return }
            boot = Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, 0)
            handler.post {
                try {
                    if (destroyed) return@post
                    // The Flutter v4 migration must have completed before opt-in.
                    db = SQLiteDatabase.openDatabase(getDatabasePath("diligent_life.db").path, null, SQLiteDatabase.OPEN_READWRITE)
                    val rebase = getSharedPreferences("daily_steps",MODE_PRIVATE).getBoolean("rebase",false)
                    db!!.rawQuery("SELECT boot,counter,sample,date FROM step_cursor WHERE id=1", null).use { c ->
                        if (!rebase && c.moveToFirst()) cursor = StepCursor(c.getInt(0), c.getLong(1), c.getLong(2), c.getString(3))
                    }
                    check(sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, 30_000_000, handler))
                    running = !destroyed
                    if (destroyed) sensors.unregisterListener(this) else error = null
                } catch (e: Exception) { error = "sensor_storage"; stopSelf() }
            }
        } catch (e: Exception) { error = "start_restricted"; stopSelf() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onFlushCompleted(sensor: Sensor) { completeFlush() }
    private fun completeFlush() {
        handler.removeCallbacks(flushTimeout)
        persist()
        val results = flushResults.toList()
        flushResults.clear()
        Handler(Looper.getMainLooper()).post { results.forEach { it(error != "storage_failed") } }
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (suspended || destroyed) return
        if (!allowed(this)) { error = "permission_revoked"; stopSelf(); return }
        val raw = event.values.firstOrNull() ?: return
        if (!raw.isFinite()) return
        val wall = System.currentTimeMillis() - (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000
        val date = Instant.ofEpochMilli(wall).atZone(ZoneId.systemDefault()).toLocalDate().toString()
        val next = StepCursor(boot, raw.toLong(), event.timestamp, date)
        val decision = StepCounterPolicy.decide(cursor, next)
        if (!decision.accept) return
        val old = pending[date]
        // Preserve partial/reset/boundary warnings rather than replacing with observed.
        pending[date] = Triple((old?.first ?: 0) + decision.delta,
            if (old != null && old.second != "observed") old.second else decision.coverage,
            (old?.third ?: 0L) + if(decision.coverage == "boundary") decision.delta else 0L)
        cursor = next
        if (!scheduled) { scheduled = true; handler.postDelayed(flushTask, 30_000) }
    }

    private fun persist() {
        val database = db ?: return
        val latest = cursor ?: return
        if (pending.isEmpty()) return
        try {
            database.beginTransaction()
            for ((date, value) in pending) {
                val now = Instant.now().toString()
                database.execSQL("INSERT OR IGNORE INTO daily_steps(date,steps,coverage,updatedAt) VALUES(?,0,?,?)", arrayOf<Any>(date, value.second, now))
                database.execSQL("UPDATE daily_steps SET steps=steps+?, uncertainSteps=uncertainSteps+?, coverage=CASE WHEN coverage='observed' THEN ? ELSE coverage END, updatedAt=? WHERE date=?", arrayOf<Any>(value.first, value.third, value.second, now, date))
            }
            database.execSQL("INSERT OR REPLACE INTO step_cursor(id,boot,counter,sample,date) VALUES(1,?,?,?,?)", arrayOf<Any>(latest.boot,latest.counter,latest.sample,latest.date))
            database.setTransactionSuccessful()
            database.endTransaction()
            pending.clear()
            val prefs = getSharedPreferences("daily_steps",MODE_PRIVATE)
            if (prefs.getBoolean("enabled",false)) prefs.edit().putBoolean("rebase",false).apply()
        } catch (e: Exception) { error = "storage_failed" }
        finally { if (database.inTransaction()) database.endTransaction() }
    }

    override fun onDestroy() {
        destroyed = true
        running = false
        if (::sensors.isInitialized) sensors.unregisterListener(this)
        if (::handler.isInitialized) {
            handler.removeCallbacks(flushTask)
            handler.post { sensors.unregisterListener(this); completeFlush(); db?.close(); db = null; worker.quitSafely() }
        }
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) { super.onTaskRemoved(rootIntent) }
    companion object {
        @Volatile var running = false
        @Volatile var error: String? = null
        @Volatile var instance: StepTrackingService? = null
        fun allowed(context: Context) = Build.VERSION.SDK_INT < 29 || context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        fun flush(result: (Boolean) -> Unit) {
            val service = instance
            if (service == null || !service::handler.isInitialized) { result(true); return }
            service.handler.post {
                service.flushResults.add(result)
                if (!service.sensors.flush(service)) service.completeFlush()
                else service.handler.postDelayed(service.flushTimeout, 5000)
            }
        }
        fun pauseRecording(result: (Boolean) -> Unit) {
            val service = instance
            if (service == null || !service::handler.isInitialized) { result(true); return }
            service.handler.post {
                service.suspended = true
                service.sensors.unregisterListener(service)
                service.handler.removeCallbacks(service.flushTask)
                service.scheduled = false
                service.persist()
                Handler(Looper.getMainLooper()).post { result(error != "storage_failed") }
            }
        }
        fun resume() {
            val service = instance ?: return
            if (!service::handler.isInitialized) return
            service.handler.post {
                if (service.suspended && allowed(service)) {
                    val sensor = service.sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                    if (sensor != null) {
                        service.suspended = false
                        if (!service.sensors.registerListener(service,sensor,SensorManager.SENSOR_DELAY_NORMAL,30_000_000,service.handler)) {
                            error = "sensor_restart_failed"
                            service.stopSelf()
                        }
                    }
                }
            }
        }
        fun start(context: Context) {
            if (!allowed(context)) return
            val intent = Intent(context, StepTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
    }
    init { instance = this }
}

class StepBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!context.getSharedPreferences("daily_steps", Context.MODE_PRIVATE).getBoolean("enabled", false)) return
        try { StepTrackingService.start(context) } catch (e: Exception) { StepTrackingService.error = "boot_restricted" }
    }
}
