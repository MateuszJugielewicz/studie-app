package com.easysesh.app.services

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.easysesh.app.BuildConfig
import com.easysesh.app.MainActivity
import com.easysesh.app.R
import com.easysesh.app.core.L10n
import com.easysesh.app.model.Booking
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.concurrent.TimeUnit

/** Where a tapped notification should take the user. */
sealed class DeepLink {
    data class BookingLink(val id: String) : DeepLink()
    data class ConversationLink(val id: String) : DeepLink()
    data class StudioLink(val id: String) : DeepLink()

    companion object {
        fun from(conversationId: String?, bookingId: String?, studioId: String?): DeepLink? = when {
            !conversationId.isNullOrEmpty() -> ConversationLink(conversationId)
            !bookingId.isNullOrEmpty() -> BookingLink(bookingId)
            !studioId.isNullOrEmpty() -> StudioLink(studioId)
            else -> null
        }

        fun from(intent: Intent?): DeepLink? =
            intent?.let { from(it.getStringExtra("conversation_id"), it.getStringExtra("booking_id"), it.getStringExtra("studio_id")) }
    }
}

/**
 * Remote push (Firebase Cloud Messaging, sent by the `send-push` edge function) plus local
 * session reminders. Firebase is optional: without its keys in local.properties push is off.
 */
object PushNotifications {
    private const val CHANNEL_ID = "easysesh"
    private const val REMINDER_TAG = "session-reminder"

    var onToken: ((String) -> Unit)? = null
    /** Shows the Android 13+ notification permission prompt; set by MainActivity. */
    var permissionRequester: (() -> Unit)? = null

    val isFirebaseConfigured: Boolean
        get() = BuildConfig.FIREBASE_APP_ID.isNotEmpty() && BuildConfig.FIREBASE_API_KEY.isNotEmpty() && BuildConfig.FIREBASE_PROJECT_ID.isNotEmpty()

    fun setUp(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "EasySesh", NotificationManager.IMPORTANCE_HIGH))
        if (isFirebaseConfigured && FirebaseApp.getApps(context).isEmpty()) {
            val options = FirebaseOptions.Builder()
                .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                .setApiKey(BuildConfig.FIREBASE_API_KEY)
                .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                .build()
            FirebaseApp.initializeApp(context, options)
        }
    }

    /** Asks for the token (the permission itself is requested by MainActivity on Android 13+). */
    fun register() {
        if (!isFirebaseConfigured) return
        runCatching { FirebaseMessaging.getInstance().token.addOnSuccessListener { onToken?.invoke(it) } }
    }

    /** Asks for permission to show notifications (Android 13+), then registers for push. */
    fun requestAuthorization(context: Context) {
        if (!canNotify(context)) permissionRequester?.invoke()
        register()
    }

    fun canNotify(context: Context) =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Shows a notification banner. */
    fun show(context: Context, id: Int, title: String, body: String, extras: Map<String, String>) {
        if (!canNotify(context)) return
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            extras.forEach { (k, v) -> putExtra(k, v) }
        }
        val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(id, notification) }
    }

    // MARK: Session reminders

    fun scheduleReminders(context: Context, bookings: List<Booking>) {
        val work = WorkManager.getInstance(context)
        work.cancelAllWorkByTag(REMINDER_TAG)
        val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(L10n.locale())
        for (booking in bookings) {
            for (hoursBefore in listOf(24, 2)) {
                val fire = booking.startsAt.minusSeconds(hoursBefore * 3600L)
                val delay = fire.toEpochMilli() - Instant.now().toEpochMilli()
                if (delay <= 0) continue
                val title = if (hoursBefore == 24) L10n.tr("Session tomorrow") else L10n.tr("Session in 2 hours")
                val body = L10n.format("%@ at %@, %@.", booking.sessionTypeName, booking.studioName,
                    time.format(booking.startsAt.atZone(ZoneId.systemDefault())))
                val request = OneTimeWorkRequestBuilder<ReminderWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .addTag(REMINDER_TAG)
                    .setInputData(Data.Builder().putString("title", title).putString("body", body).putString("booking_id", booking.id).build())
                    .build()
                work.enqueueUniqueWork("reminder-${booking.id}-$hoursBefore", ExistingWorkPolicy.REPLACE, request)
            }
        }
    }

    fun cancelAllReminders(context: Context) {
        WorkManager.getInstance(context).cancelAllWorkByTag(REMINDER_TAG)
    }
}

class ReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val bookingId = inputData.getString("booking_id") ?: return Result.success()
        PushNotifications.show(applicationContext, bookingId.hashCode(), inputData.getString("title") ?: "", inputData.getString("body") ?: "",
            mapOf("booking_id" to bookingId))
        return Result.success()
    }
}

/** Receives pushes from the `send-push` edge function (FCM data: title, body, booking_id, …). */
class EasySeshMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        PushNotifications.onToken?.invoke(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = message.notification?.title ?: data["title"] ?: "EasySesh"
        val body = message.notification?.body ?: data["body"] ?: ""
        val extras = listOf("booking_id", "conversation_id", "studio_id").mapNotNull { key -> data[key]?.let { key to it } }.toMap()
        PushNotifications.show(this, (message.messageId ?: title).hashCode(), title, body, extras)
    }
}
