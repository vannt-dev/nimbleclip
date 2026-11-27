package com.vannt.nimbleclip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/// Keeps the app's process working while it is off screen.
///
/// The transfers themselves belong to the system and carry on without the app.
/// What needs the app is what follows them: joining the parts of a video,
/// converting audio to MP3, fetching a stream segment by segment, rendering a
/// slideshow. Android freezes or ends a process that is in the background with
/// nothing to show for it, and a download then sat unfinished until the app
/// was opened again. A foreground service is the system's own way of saying
/// "this is still working": it puts a notification up, and the process is left
/// alone for as long as it runs.
///
/// It does nothing itself. The Dart side starts it when work begins and stops
/// it when the last piece is done. Quick download starts it too, from the
/// moment a link is shared, so each starter is counted as a holder and the
/// service stays until the last one lets go.
class KeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "NimbleClip"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        try {
            val notification = notification(this, title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            running = true
        } catch (error: Exception) {
            // Android 12 and later refuse a foreground service started while
            // the app is in the background. The work goes on as it did before
            // there was a service.
            stopSelf()
            return START_NOT_STICKY
        }
        holdWakeLock()
        // Not restarted by the system: it would come back with nothing to do.
        return START_NOT_STICKY
    }

    /// With the screen off the processor may sleep even under a foreground
    /// service, and a join or a conversion would stall half way.
    private fun holdWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nimbleclip:keepalive").apply {
            setReferenceCounted(false)
            // A ceiling, in case the stop never arrives.
            acquire(WAKE_LOCK_LIMIT_MS)
        }
    }

    /// Android 15 gives a data-sync service six hours in a day and then asks
    /// it to stop; staying would end the app.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    /// The user swiped the app away: that ends the work, so this goes with it.
    /// Not for the task Quick download passes through: it closes as soon as
    /// the link is handed over, and the download it started is the work.
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (rootIntent?.component?.className == QuickDownloadActivity::class.java.name) return
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        synchronized(holders) { holders.clear() }
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "background_work"
        private const val NOTIFICATION_ID = 7301
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val WAKE_LOCK_LIMIT_MS = 6L * 60 * 60 * 1000

        /// Who asked for the service when the caller does not say.
        const val DEFAULT_HOLDER = "downloads"

        private val holders = mutableSetOf<String>()

        /// Whether the service is up in the foreground. A second start then
        /// only changes the notification: the system refuses a foreground
        /// service started from the background, and the refusal would take
        /// the running one down with it.
        @Volatile
        private var running = false

        /// False when the system refused, which it does for a start from the
        /// background.
        fun start(
            context: Context,
            title: String,
            text: String,
            holder: String = DEFAULT_HOLDER,
        ): Boolean {
            synchronized(holders) { holders.add(holder) }
            if (running) {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, notification(context, title, text))
                return true
            }
            return try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, KeepAliveService::class.java)
                        .putExtra(EXTRA_TITLE, title)
                        .putExtra(EXTRA_TEXT, text),
                )
                true
            } catch (error: Exception) {
                synchronized(holders) { holders.remove(holder) }
                false
            }
        }

        /// Lets go for [holder]; the service ends when nobody holds it.
        fun stop(context: Context, holder: String = DEFAULT_HOLDER) {
            val nobodyLeft = synchronized(holders) {
                holders.remove(holder)
                holders.isEmpty()
            }
            if (!nobodyLeft) return
            running = false
            context.stopService(Intent(context, KeepAliveService::class.java))
        }

        private fun notification(context: Context, title: String, text: String): Notification {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, title, NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                    },
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }
    }
}
