package com.shellx.app.platform

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Resources
import android.os.Build
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.shellx.app.MainActivity
import com.shellx.app.R
import com.shellx.core.platform.CoreLog
import com.shellx.core.push.PushPayload
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Posts and removes the "needs you" alerts (`PushAppDelegate.swift`; contracts §8). Nothing shows while the app is in
 * front (the app shows what waits), without the permission, or for a Mac this phone does not have (signed out or
 * unpaired while offline, so the relay still holds the token; ledger A-25). Each alert is tagged with its request and
 * grouped by its Mac under a summary, which leaves with the Mac's last alert. A tap opens the waiting requests.
 *
 * Thread-safe: FCM calls it on its own thread, the app's lifecycle on the main thread. No text is logged.
 */
class PushNotifier(
    context: Context,
    private val inForeground: () -> Boolean,
    private val knownMachines: suspend () -> Set<String>?,
    /** The alerts Android lists now (tests give their own: Android lists a new one only once its service got to it). */
    private val active: () -> List<StatusBarNotification> = {
        context.getSystemService(NotificationManager::class.java).activeNotifications.toList()
    },
) {
    private val app = context.applicationContext
    private val compat = NotificationManagerCompat.from(app)
    private val lock = Any()

    /**
     * The request ids of the alerts this process posted and has not removed, per Mac (under [lock]). Android lists a
     * new alert only once its service got to it, so in a burst (`needs_you r2`, then `resolved r1`) only this knows r2
     * is there; cancelling the summary then would take r2 with it (review C m-1).
     */
    private val posted = HashMap<String, MutableSet<String>>()

    suspend fun handle(payload: PushPayload) {
        when (payload) {
            is PushPayload.NeedsYou -> needsYou(payload)
            is PushPayload.Resolved -> resolved(payload)
        }
    }

    /** The app came to the front, which shows what waits: every alert goes (iPhone `removeAllDeliveredNotifications`). */
    fun clearAll() {
        synchronized(lock) {
            compat.cancelAll()
            posted.clear()
        }
    }

    private suspend fun needsYou(payload: PushPayload.NeedsYou) {
        if (inForeground()) return
        if (!allowed()) return
        val known = try {
            withTimeoutOrNull(KNOWN_MACHINES_TIMEOUT) { knownMachines() }
        } catch (e: CancellationException) {
            currentCoroutineContext().ensureActive()
            null
        } catch (e: Exception) {
            null
        }
        if (known != null && payload.machineId !in known) {
            CoreLog.log("push_unknown_mac")
            return
        }
        ensureChannel(app)
        val res = app.resources
        val title = res.getString(R.string.push_title)
        val text = text(payload, res)
        val tap = PendingIntent.getActivity(
            app, payload.requestId.hashCode(), tapIntent(app), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun builder() = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_shellx)
            .setContentTitle(title)
            .setContentText(text)
            .setGroup(payload.machineId)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(tap)
        val alert = builder().build()
        val summary = builder()
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .build()
        synchronized(lock) {
            // Again, under the lock clearAll takes: the app may have come to the front (and cleared the alerts) while
            // the paired Macs were read (review C m-2).
            if (inForeground()) return
            post(payload.requestId, NOTIFICATION_ID, alert)
            post(payload.machineId, SUMMARY_ID, summary)
            posted.getOrPut(payload.machineId) { mutableSetOf() } += payload.requestId
        }
        CoreLog.log("push_posted")
    }

    private fun resolved(payload: PushPayload.Resolved) {
        synchronized(lock) {
            compat.cancel(payload.requestId, NOTIFICATION_ID)
            val mine = posted[payload.machineId]
            mine?.remove(payload.requestId)
            if (mine?.isEmpty() == true) posted.remove(payload.machineId)
            // The Mac still has alerts when this process posted one, or Android lists one (posted by an earlier process).
            // The cancel may not have reached the list yet, so the resolved alert never counts.
            val others = mine?.isNotEmpty() == true || active().any {
                it.id == NOTIFICATION_ID && it.tag != payload.requestId && it.notification.group == payload.machineId
            }
            if (!others) compat.cancel(payload.machineId, SUMMARY_ID)
        }
    }

    private fun allowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission") // allowed() was checked; a permission taken away since throws, and is caught.
    private fun post(tag: String, id: Int, notification: Notification) {
        try {
            compat.notify(tag, id, notification)
        } catch (e: SecurityException) {
            CoreLog.log("push_post_refused")
        }
    }

    companion object {
        const val CHANNEL_ID = "needs_you"
        const val NOTIFICATION_ID = 1
        const val SUMMARY_ID = 2
        const val ACTION_OPEN_PENDING = "com.shellx.app.action.OPEN_PENDING"

        /** The paired-Mac check waits at most this long; on timeout or error the alert posts. */
        val KNOWN_MACHINES_TIMEOUT: Duration = 2.seconds

        /** The "Needs you" channel: high importance, so an alert shows as a heads-up. Kept in the app's language. */
        fun ensureChannel(context: Context) {
            val res = context.resources
            val channel = NotificationChannel(
                CHANNEL_ID, res.getString(R.string.notification_channel_needs_you), NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = res.getString(R.string.notification_channel_needs_you_description) }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        /** `push_needs_you_workspace(agent, workspaceTitle)` when [PushPayload.NeedsYou.showsWorkspace], else
         *  `push_needs_you(agent)`. */
        fun text(payload: PushPayload.NeedsYou, res: Resources): String =
            if (payload.showsWorkspace) {
                res.getString(R.string.push_needs_you_workspace, payload.agent, payload.workspaceTitle.trim())
            } else {
                res.getString(R.string.push_needs_you, payload.agent)
            }

        /** MainActivity on top of its task, asked to open the waiting requests ([PushTapInbox.isOpenPending]). */
        private fun tapIntent(context: Context): Intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN_PENDING)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
}
