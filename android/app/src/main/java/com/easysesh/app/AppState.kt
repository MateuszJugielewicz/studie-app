package com.easysesh.app

import android.content.Context
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.data.Backend
import com.easysesh.app.model.AppNotification
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.model.Booking
import com.easysesh.app.model.ChangelogEntry
import com.easysesh.app.model.ModerationWarning
import com.easysesh.app.model.Studio
import com.easysesh.app.model.UserAccount
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.AppPreferences
import com.easysesh.app.services.DeepLink
import com.easysesh.app.services.LocationService
import com.easysesh.app.services.PushNotifications
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant

enum class AppTab {
    // Artist
    Discover, Bookings,
    // Studio
    Dashboard, Calendar,
    // Shared
    Messages, Notifications, Profile,
}

/** Sign in or sign up, as an artist or a studio owner. */
data class AuthRoute(val mode: Mode, val role: UserRole) {
    enum class Mode { SignIn, SignUp }
    val id get() = "$mode-${role.raw}"
}

/** App-wide state, the same as the iOS app's AppState. */
class AppState(private val context: Context) {
    val backend = Backend()
    val preferences = AppPreferences(context)
    val location = LocationService(context)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var account by mutableStateOf<UserAccount?>(null)
        private set
    var artistProfile by mutableStateOf<ArtistProfile?>(null)
    var ownedStudio by mutableStateOf<Studio?>(null)
    var isBootstrapping by mutableStateOf(true)
        private set
    /** True once the launch splash has faded out; pop-ups wait for it. */
    var launchFinished by mutableStateOf(false)
    /** Browsing studios without an account. Booking and messaging ask the guest to sign up first. */
    var isGuest by mutableStateOf(false)
    /** Set from anywhere in guest mode to open sign-up. */
    var guestAuthRequest by mutableStateOf<AuthRoute?>(null)
    /** Role picked before a browser sign-in (Apple / Google), applied when it returns. */
    var pendingOAuthRole: UserRole = UserRole.Artist

    var selectedTab by mutableStateOf(AppTab.Discover)
    /** Set after opening a password-reset link: the user must choose a new password. */
    var needsNewPassword by mutableStateOf(false)
    var pendingDeepLink by mutableStateOf<DeepLink?>(null)
    /** Bumped when a tab is tapped again, so it returns to its first screen. */
    var tabResetCounter by mutableStateOf(mapOf<AppTab, Int>())

    var notifications by mutableStateOf<List<AppNotification>>(emptyList())
    var unreadMessages by mutableStateOf(0)
    val unreadNotifications by derivedStateOf { notifications.count { !it.isRead } }

    val role: UserRole get() = account?.role ?: UserRole.Artist

    /** Terms version the user must have accepted: the newer of the app's and the server's. */
    var requiredTermsVersion by mutableStateOf(LegalDocument.CURRENT_VERSION)
        private set
    /** Update notes from the EasySesh team, newest first, for this user's role. */
    var changelog by mutableStateOf<List<ChangelogEntry>>(emptyList())
        private set
    /** Warnings from the EasySesh team the user hasn't acknowledged yet. */
    var warnings by mutableStateOf<List<ModerationWarning>>(emptyList())
        private set
    private var changelogSeenAt by mutableStateOf<Instant?>(null)

    val needsTermsAcceptance: Boolean
        get() {
            val account = account ?: return false
            if (account.role == UserRole.Admin) return false
            return (account.acceptedTermsVersion ?: "") < requiredTermsVersion
        }

    /** The latest legal update the user hasn't accepted yet, to show what changed. */
    val pendingLegalUpdate: ChangelogEntry?
        get() = changelog.firstOrNull { it.isLegalUpdate && it.version > (account?.acceptedTermsVersion ?: "") }

    /** Changelog entries the user hasn't seen yet (only ones published since they joined). */
    val unseenChangelog: List<ChangelogEntry>
        get() {
            val account = account ?: return emptyList()
            val seen = changelogSeenAt ?: account.createdAt
            return changelog.filter { it.publishedAt.isAfter(seen) }
        }

    init {
        PushNotifications.onToken = { token -> scope.launch { runCatching { backend.registerPushToken(token) } } }
    }

    fun markChangelogSeen() {
        val account = account ?: return
        val newest = changelog.firstOrNull()?.publishedAt ?: return
        changelogSeenAt = newest
        preferences.setChangelogSeenAt(account.id, newest.toEpochMilli())
    }

    suspend fun acknowledgeWarning(warning: ModerationWarning) {
        runCatching { backend.acknowledgeWarning(warning.id) }
        warnings = warnings.filter { it.id != warning.id }
    }

    /** Checks for new update notes, legal updates and warnings. */
    suspend fun refreshUpdates() {
        val account = account ?: return
        if (account.role != UserRole.Admin) runCatching { backend.unacknowledgedWarnings() }.getOrNull()?.let { warnings = it }
        changelogSeenAt = preferences.changelogSeenAt(account.id)?.let { Instant.ofEpochMilli(it) }
        runCatching { backend.currentTermsVersion() }.getOrNull()?.let {
            requiredTermsVersion = LegalDocument.newest(LegalDocument.CURRENT_VERSION, it)
        }
        runCatching { backend.changelog() }.getOrNull()?.let { entries -> changelog = entries.filter { it.isFor(account.role) } }
    }

    // MARK: Session

    suspend fun bootstrap() {
        try {
            backend.restoreSession()?.let { didAuthenticate(it) }
        } finally {
            isBootstrapping = false
        }
    }

    /** A sign-in link (email confirmation, password reset or Apple/Google browser sign-in) came back. */
    suspend fun completeAuthLink(isRecovery: Boolean) {
        val restored = backend.restoreSession()
        if (restored != null) {
            val account = if (pendingOAuthRole == UserRole.StudioOwner) runCatching { backend.finishSocialSignIn(pendingOAuthRole) }.getOrDefault(restored) else restored
            didAuthenticate(account)
        }
        pendingOAuthRole = UserRole.Artist
        needsNewPassword = isRecovery
    }

    suspend fun didAuthenticate(account: UserAccount) {
        this.account = account
        isGuest = false
        guestAuthRequest = null
        selectedTab = if (account.role == UserRole.StudioOwner) AppTab.Dashboard else AppTab.Discover
        when (account.role) {
            UserRole.Artist -> artistProfile = runCatching { backend.artistProfile(account.id) }.getOrNull()
            UserRole.StudioOwner -> ownedStudio = runCatching { backend.ownedStudio() }.getOrNull()
            UserRole.Admin -> Unit
        }
        refreshUpdates()
        refreshBadges()
        if (account.settings.pushEnabled) PushNotifications.register()
    }

    fun updateAccount(account: UserAccount) {
        this.account = account
    }

    suspend fun signOut() {
        backend.signOut()
        account = null
        artistProfile = null
        ownedStudio = null
        notifications = emptyList()
        unreadMessages = 0
        PushNotifications.cancelAllReminders(context)
    }

    suspend fun deleteAccount() {
        backend.deleteAccount()
        signOut()
    }

    // MARK: Badges & notifications

    suspend fun refreshBadges() {
        if (account == null) return
        refreshUpdates()
        runCatching { backend.notifications() }.getOrNull()?.let { notifications = it }
        runCatching { backend.conversations() }.getOrNull()?.let { list -> unreadMessages = list.sumOf { it.badgeCount(role) } }
    }

    suspend fun markNotificationRead(note: AppNotification) {
        runCatching { backend.markNotificationRead(note.id) }
        notifications = notifications.map { if (it.id == note.id) it.copy(isRead = true) else it }
    }

    suspend fun markAllNotificationsRead() {
        runCatching { backend.markAllNotificationsRead() }
        notifications = notifications.map { it.copy(isRead = true) }
    }

    suspend fun deleteNotification(note: AppNotification) {
        notifications = notifications.filter { it.id != note.id }
        runCatching { backend.deleteNotification(note.id) }
    }

    suspend fun deleteAllNotifications() {
        notifications = emptyList()
        runCatching { backend.deleteAllNotifications() }
    }

    // MARK: Navigation

    fun open(link: DeepLink) {
        selectedTab = when (link) {
            is DeepLink.BookingLink -> if (role == UserRole.StudioOwner) AppTab.Calendar else AppTab.Bookings
            is DeepLink.ConversationLink -> AppTab.Messages
            is DeepLink.StudioLink -> if (role == UserRole.StudioOwner) AppTab.Dashboard else AppTab.Discover
        }
        pendingDeepLink = link
    }

    fun consumeDeepLink(matching: (DeepLink) -> Boolean): DeepLink? {
        val link = pendingDeepLink ?: return null
        if (!matching(link)) return null
        pendingDeepLink = null
        return link
    }

    /** Selecting the current tab again returns it to its first screen. */
    fun selectTab(tab: AppTab) {
        if (tab == selectedTab) tabResetCounter = tabResetCounter + (tab to ((tabResetCounter[tab] ?: 0) + 1))
        selectedTab = tab
    }

    /** Keeps local "session starts soon" reminders in sync with the artist's bookings. */
    fun syncReminders(bookings: List<Booking>) {
        if (account?.settings?.reminders == false) {
            PushNotifications.cancelAllReminders(context)
            return
        }
        PushNotifications.scheduleReminders(context, bookings.filter { it.isUpcoming })
    }
}
