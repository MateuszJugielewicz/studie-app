package com.easysesh.app.data

import android.content.Intent
import com.easysesh.app.BuildConfig
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.core.PasswordPolicy
import com.easysesh.app.core.PostgresDate
import com.easysesh.app.core.PostgresJson
import com.easysesh.app.model.*
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.providers.Apple
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.serializer.KotlinXSerializer
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import java.time.Instant
import java.util.UUID

/** Details the payment sheet needs to charge a booking. */
data class PaymentIntentInfo(
    val bookingId: String,
    val clientSecret: String,
    val customerId: String?,
    val ephemeralKey: String?,
    val amount: Int,
    val currency: String,
    /** Studios on request-to-book authorise now and capture on acceptance. */
    val captureLater: Boolean,
)

/**
 * Everything the app needs from the server: Supabase Auth, Postgres (with row-level security),
 * Storage, Realtime and Edge Functions. A 1:1 port of the iOS app's SupabaseBackend.
 */
class Backend {
    val isConfigured = BuildConfig.SUPABASE_URL.isNotEmpty() && BuildConfig.SUPABASE_ANON_KEY.isNotEmpty()

    val client: SupabaseClient = createSupabaseClient(
        supabaseUrl = BuildConfig.SUPABASE_URL.ifEmpty { "https://invalid.supabase.co" },
        supabaseKey = BuildConfig.SUPABASE_ANON_KEY.ifEmpty { "missing" },
    ) {
        defaultSerializer = KotlinXSerializer(PostgresJson)
        install(Auth) {
            scheme = REDIRECT_SCHEME
            host = REDIRECT_HOST
        }
        install(Postgrest)
        install(Realtime)
        install(Storage)
    }

    private val http = HttpClient(OkHttp)

    // MARK: Helpers

    private fun userId(): String = client.auth.currentUserOrNull()?.id ?: throw BackendError.NotAuthenticated

    private suspend fun <T> mapped(work: suspend () -> T): T = try {
        work()
    } catch (error: BackendError) {
        throw error
    } catch (error: CancellationException) {
        throw error
    } catch (error: PostgrestRestException) {
        throw map(error.error, error.code)
    } catch (error: AuthRestException) {
        val message = error.errorDescription.ifEmpty { error.message ?: "" }
        when {
            message.contains("invalid login", ignoreCase = true) -> throw BackendError.InvalidCredentials
            message.contains("already registered", ignoreCase = true) -> throw BackendError.EmailInUse
            else -> throw BackendError.Server(message)
        }
    } catch (error: RestException) {
        throw map(error.error, null)
    } catch (error: Exception) {
        throw BackendError.Server(error.message ?: "Something went wrong. Please try again.")
    }

    private fun map(message: String, code: String?): BackendError = when (message) {
        "slot_unavailable" -> BackendError.SlotUnavailable
        "forbidden" -> BackendError.Forbidden
        "not_found" -> BackendError.NotFound
        "account_suspended" -> BackendError.AccountSuspended
        else -> when (code) {
            // Raised with `raise exception using errcode = 'P0001'` → user-facing message.
            "23P01" -> BackendError.SlotUnavailable
            "42501" -> BackendError.Forbidden
            else -> BackendError.Validation(message)
        }
    }

    /** Calls an edge function (same JSON contract as iOS). */
    private suspend fun invokeRaw(function: String, body: JsonObject): JsonElement = mapped {
        val token = client.auth.currentAccessTokenOrNull() ?: BuildConfig.SUPABASE_ANON_KEY
        val response = http.post("${BuildConfig.SUPABASE_URL}/functions/v1/$function") {
            header("Authorization", "Bearer $token")
            header("apikey", BuildConfig.SUPABASE_ANON_KEY)
            contentType(ContentType.Application.Json)
            setBody(body.toString())
        }
        val text = response.bodyAsText()
        if (!response.status.isSuccess()) {
            val message = runCatching { Json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()
            throw map(message ?: "Request failed.", null)
        }
        Json.parseToJsonElement(text.ifEmpty { "{}" })
    }

    private suspend inline fun <reified T : Any> invoke(function: String, noinline body: JsonObjectBuilder.() -> Unit = {}): T =
        PostgresJson.decodeFromJsonElement(invokeRaw(function, buildJsonObject(body)))

    private suspend inline fun <reified T : Any> rpc(function: String, noinline params: JsonObjectBuilder.() -> Unit = {}): T = mapped {
        client.postgrest.rpc(function, buildJsonObject(params)).decodeAs<T>()
    }

    private suspend fun rpcVoid(function: String, params: JsonObjectBuilder.() -> Unit = {}) {
        mapped { client.postgrest.rpc(function, buildJsonObject(params)) }
    }

    private suspend fun account(id: String): UserAccount = mapped {
        client.from("profiles").select { filter { eq("id", id) } }.decodeSingle<UserAccount>()
    }

    private suspend fun ensureActive(account: UserAccount): UserAccount {
        var result = account
        // A suspension whose period is over is lifted right away instead of waiting for the job.
        val until = result.statusUntil
        if (result.status != AccountStatus.Active && until != null && !until.isAfter(Instant.now())) {
            runCatching { rpc<UserAccount>("lift_my_expired_restriction") }.getOrNull()?.let { result = it }
        }
        if (result.status != AccountStatus.Active) {
            runCatching { client.auth.signOut() }
            throw BackendError.AccountRestricted(result.status == AccountStatus.Banned, result.statusUntil, result.statusReason)
        }
        return result
    }

    // MARK: Auth

    suspend fun restoreSession(): UserAccount? {
        runCatching { client.auth.awaitInitialization() }
        val user = client.auth.currentUserOrNull() ?: return null
        return runCatching { ensureActive(account(user.id)) }.getOrNull()
    }

    /** Handles easysesh://auth-callback links (email confirmation, password reset, OAuth). */
    fun handleDeeplink(intent: Intent, onSession: () -> Unit) {
        client.handleDeeplinks(intent) { onSession() }
    }

    suspend fun signUp(email: String, password: String, role: UserRole): UserAccount {
        PasswordPolicy.problem(password)?.let { throw BackendError.Validation(it) }
        // The sign-up form requires accepting the terms; the version is stored as the consent record.
        val user = mapped {
            client.auth.signUpWith(Email, redirectUrl = REDIRECT_URL) {
                this.email = email
                this.password = password
                data = buildJsonObject {
                    put("role", role.raw)
                    put("terms_version", LegalDocument.CURRENT_VERSION)
                }
            }
        }
        if (client.auth.currentSessionOrNull() == null) {
            throw BackendError.Validation("We sent you a confirmation email. Open the link, then sign in.")
        }
        return account(user?.id ?: userId())
    }

    suspend fun signIn(email: String, password: String): UserAccount {
        mapped {
            client.auth.signInWith(Email) {
                this.email = email
                this.password = password
            }
        }
        return ensureActive(account(userId()))
    }

    /** Native Google sign-in (Credential Manager ID token). */
    suspend fun signInWithGoogleIdToken(idToken: String, nonce: String?, role: UserRole): UserAccount {
        mapped {
            client.auth.signInWith(IDToken) {
                this.idToken = idToken
                provider = Google
                this.nonce = nonce
            }
        }
        return finishSocialSignIn(role)
    }

    /** Browser sign-in (Apple on Android, or Google without a client ID). Finishes in [handleDeeplink]. */
    suspend fun startOAuth(provider: String) {
        mapped {
            if (provider == "apple") client.auth.signInWith(Apple, redirectUrl = REDIRECT_URL)
            else client.auth.signInWith(Google, redirectUrl = REDIRECT_URL)
        }
    }

    /** Social sign-up creates an artist by default; brand-new accounts may switch to studio owner once. */
    suspend fun finishSocialSignIn(role: UserRole): UserAccount {
        if (role == UserRole.StudioOwner) runCatching { rpcVoid("claim_role") { put("p_role", role.raw) } }
        return ensureActive(account(userId()))
    }

    suspend fun sendPasswordReset(email: String) {
        mapped { client.auth.resetPasswordForEmail(email, redirectUrl = REDIRECT_URL) }
    }

    suspend fun signOut() {
        runCatching { client.auth.signOut() }
    }

    suspend fun changePassword(newPassword: String) {
        PasswordPolicy.problem(newPassword)?.let { throw BackendError.Validation(it) }
        mapped { client.auth.updateUser { password = newPassword } }
    }

    suspend fun deleteAccount() {
        invokeRaw("delete-account", buildJsonObject { })
        runCatching { client.auth.signOut() }
    }

    suspend fun acceptTerms(version: String): UserAccount = rpc("accept_terms") { put("p_version", version) }

    /** GDPR data export: everything stored about the signed-in user, as pretty-printed JSON. */
    suspend fun exportPersonalData(): String {
        // Built in the database (export_my_data), so it works without the edge functions deployed.
        val json: JsonElement = rpc("export_my_data")
        return Json { prettyPrint = true }.encodeToString(JsonElement.serializer(), json)
    }

    suspend fun updateSettings(settings: UserSettings): UserAccount {
        val id = userId()
        return mapped {
            client.from("profiles").update({ set("settings", PostgresJson.encodeToJsonElement(UserSettings.serializer(), settings)) }) {
                select()
                filter { eq("id", id) }
            }.decodeSingle()
        }
    }

    // MARK: Profiles

    suspend fun artistProfile(id: String): ArtistProfile? = mapped {
        client.from("artist_profiles").select { filter { eq("id", id) }; limit(1) }.decodeList<ArtistProfile>().firstOrNull()
    }

    suspend fun saveArtistProfile(profile: ArtistProfile): ArtistProfile = mapped {
        client.from("artist_profiles").upsert(profile) { select() }.decodeSingle()
    }

    suspend fun uploadImage(data: ByteArray, folder: String): String {
        val id = userId()
        // Storage policies only allow writes under the caller's own user-id prefix.
        val path = "${id.lowercase()}/$folder/${UUID.randomUUID().toString().lowercase()}.jpg"
        return mapped {
            val bucket = client.storage.from("media")
            bucket.upload(path, data) {
                upsert = false
                contentType = ContentType.Image.JPEG
            }
            bucket.publicUrl(path)
        }
    }

    // MARK: Studios

    suspend fun publishedStudios(): List<Studio> = mapped {
        client.from("studios").select {
            filter {
                eq("status", StudioStatus.Approved.raw)
                eq("is_active", true)
            }
            order("name", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun studio(id: String): Studio = mapped {
        client.from("studios").select { filter { eq("id", id) } }.decodeSingle()
    }

    suspend fun ownedStudio(): Studio? {
        val id = userId()
        return mapped { client.from("studios").select { filter { eq("owner_id", id) }; limit(1) }.decodeList<Studio>().firstOrNull() }
    }

    /** Moderation columns are protected by a trigger; the owner can only change listing content. */
    suspend fun saveStudio(studio: Studio): Studio = mapped {
        client.from("studios").upsert(studio.normalized()) { select() }.decodeSingle()
    }

    suspend fun submitStudioForReview(id: String): Studio = rpc("submit_studio_for_review") { put("p_studio_id", id) }

    suspend fun setStudioActive(id: String, isActive: Boolean): Studio =
        rpc("set_studio_active") { put("p_studio_id", id); put("p_active", isActive) }

    suspend fun payoutAccount(studioId: String): PayoutAccount? = mapped {
        client.from("studio_payout_accounts").select { filter { eq("studio_id", studioId) }; limit(1) }.decodeList<PayoutAccount>().firstOrNull()
    }

    @Serializable
    private data class PayoutAccountResponse(val account: PayoutAccount, val onboardingUrl: String? = null)

    suspend fun savePayoutAccount(account: PayoutAccount): PayoutAccount =
        invoke<PayoutAccountResponse>("payout-account") {
            put("studio_id", account.studioId); put("account_holder", account.accountHolder); put("action", "save")
        }.account

    /** Stripe's identity check (hosted onboarding link). */
    suspend fun payoutOnboardingUrl(studioId: String): String? =
        invoke<PayoutAccountResponse>("payout-account") { put("studio_id", studioId); put("action", "onboarding_link") }.onboardingUrl

    /** Adds the bank account (as a Stripe token made in the app) to the studio's Stripe account. */
    suspend fun savePayoutBank(studioId: String, holder: String, bankToken: String): PayoutAccount =
        invoke<PayoutAccountResponse>("payout-account") {
            put("studio_id", studioId); put("account_holder", holder); put("bank_token", bankToken); put("action", "bank")
        }.account

    /** Re-reads the payout status from Stripe (after the studio returns from Stripe's pages). */
    suspend fun syncPayoutAccount(studioId: String): PayoutAccount =
        invoke<PayoutAccountResponse>("payout-account") { put("studio_id", studioId); put("action", "sync") }.account

    @Serializable
    private data class BusyRow(val studioId: String, val startsAt: com.easysesh.app.core.PgInstant, val endsAt: com.easysesh.app.core.PgInstant)

    /** Occupied periods (bookings + blocks) used to compute availability. */
    suspend fun busyIntervals(studioIds: List<String>, from: Instant, to: Instant): Map<String, List<Interval>> {
        val rows: List<BusyRow> = rpc("studio_busy_intervals") {
            putJsonArray("p_studio_ids") { studioIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }
            put("p_from", PostgresDate.format(from))
            put("p_to", PostgresDate.format(to))
        }
        return rows.groupBy { it.studioId }.mapValues { (_, list) -> list.map { Interval(it.startsAt, maxOf(it.startsAt, it.endsAt)) } }
    }

    suspend fun blockedSlots(studioId: String): List<BlockedSlot> = mapped {
        client.from("blocked_slots").select {
            filter {
                eq("studio_id", studioId)
                gte("ends_at", PostgresDate.format(Instant.now()))
            }
            order("starts_at", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun addBlockedSlot(slot: BlockedSlot): BlockedSlot = mapped {
        client.from("blocked_slots").insert(slot) { select() }.decodeSingle()
    }

    suspend fun removeBlockedSlot(id: String) {
        mapped { client.from("blocked_slots").delete { filter { eq("id", id) } } }
    }

    // MARK: Bookings
    // Booking actions run as database functions. Only steps that move card money go through
    // the Stripe edge functions.

    suspend fun createBooking(request: BookingRequest): Booking = rpc("create_booking") {
        put("p_studio_id", request.studio.id)
        put("p_session_type_id", request.sessionType.id)
        put("p_starts_at", PostgresDate.format(request.startsAt))
        put("p_hours", request.hours)
        putJsonArray("p_add_ons") {
            request.addOns.filter { it.value > 0 }.forEach { (id, quantity) ->
                addJsonObject { put("id", id); put("quantity", quantity) }
            }
        }
        put("p_notes", request.notes)
    }

    /** Runs the database version first; card bookings that need a refund/capture use the edge function. */
    private suspend fun bookingAction(
        rpcName: String,
        params: JsonObjectBuilder.() -> Unit,
        edge: String,
        edgeBody: JsonObjectBuilder.() -> Unit,
    ): Booking = try {
        rpc(rpcName, params)
    } catch (error: BackendError.Validation) {
        if (error.text != "needs_payment_service") throw error
        invoke(edge, edgeBody)
    }

    @Serializable
    private data class PaymentIntentResponse(
        val clientSecret: String,
        val customerId: String? = null,
        val ephemeralKey: String? = null,
        val amount: Int,
        val currency: String,
        val captureLater: Boolean = false,
    )

    suspend fun preparePayment(bookingId: String): PaymentIntentInfo {
        val r: PaymentIntentResponse = invoke("create-payment-intent") { put("booking_id", bookingId) }
        return PaymentIntentInfo(bookingId, r.clientSecret, r.customerId, r.ephemeralKey, r.amount, r.currency.uppercase(), r.captureLater)
    }

    /** Idempotent: reads the PaymentIntent from Stripe and applies the same transition as the webhook. */
    suspend fun confirmPayment(bookingId: String): Booking = invoke("confirm-payment") { put("booking_id", bookingId) }

    suspend fun confirmCashBooking(bookingId: String): Booking = rpc("confirm_cash_booking") { put("p_booking_id", bookingId) }

    suspend fun markCashReceived(bookingId: String): Booking = rpc("mark_cash_received") { put("p_booking_id", bookingId) }

    suspend fun booking(id: String): Booking = mapped {
        client.from("bookings").select { filter { eq("id", id) } }.decodeSingle()
    }

    suspend fun artistBookings(): List<Booking> {
        val id = userId()
        return mapped {
            client.from("bookings").select {
                filter {
                    eq("artist_id", id)
                    neq("status", BookingStatus.AwaitingPayment.raw)
                }
                order("starts_at", Order.DESCENDING)
            }.decodeList()
        }
    }

    suspend fun studioBookings(studioId: String): List<Booking> = mapped {
        client.from("bookings").select {
            filter {
                eq("studio_id", studioId)
                neq("status", BookingStatus.AwaitingPayment.raw)
            }
            order("starts_at", Order.DESCENDING)
        }.decodeList()
    }

    suspend fun cancelBooking(id: String, reason: String): Booking = bookingAction(
        "cancel_booking", { put("p_booking_id", id); put("p_reason", reason) },
        "cancel-booking", { put("booking_id", id); put("reason", reason) },
    )

    suspend fun rescheduleBooking(id: String, newStart: Instant): Booking =
        rpc("reschedule_booking") { put("p_booking_id", id); put("p_starts_at", PostgresDate.format(newStart)) }

    suspend fun respondToBooking(id: String, accept: Boolean, message: String?): Booking = bookingAction(
        "respond_booking", { put("p_booking_id", id); put("p_accept", accept); put("p_message", message) },
        "respond-booking", { put("booking_id", id); put("accept", accept); put("message", message) },
    )

    /** Artist checks in on arrival (location optional). */
    suspend fun checkIn(bookingId: String, latitude: Double?, longitude: Double?): Booking = rpc("check_in_booking") {
        put("p_booking_id", bookingId)
        put("p_lat", latitude)
        put("p_lng", longitude)
    }

    /** Studio confirms the artist arrived. */
    suspend fun confirmArrival(bookingId: String): Booking = rpc("confirm_artist_arrival") { put("p_booking_id", bookingId) }

    suspend fun openDispute(bookingId: String, reason: String) =
        rpcVoid("open_dispute") { put("p_booking_id", bookingId); put("p_reason", reason) }

    // MARK: Payments

    suspend fun transactions(bookingId: String): List<PaymentTransaction> = mapped {
        client.from("transactions").select { filter { eq("booking_id", bookingId) }; order("created_at", Order.ASCENDING) }.decodeList()
    }

    suspend fun feeLedger(studioId: String): List<FeeLedgerEntry> = mapped {
        client.from("studio_fee_ledger").select { filter { eq("studio_id", studioId) }; order("created_at", Order.DESCENDING) }.decodeList()
    }

    suspend fun payouts(studioId: String): List<Payout> = mapped {
        client.from("payouts").select { filter { eq("studio_id", studioId) }; order("scheduled_for", Order.DESCENDING) }.decodeList()
    }

    // MARK: Chat

    suspend fun conversations(): List<Conversation> = mapped {
        client.from("conversations").select { order("last_message_at", Order.DESCENDING) }.decodeList()
    }

    suspend fun conversation(studioId: String, bookingId: String?): Conversation =
        rpc("get_or_create_conversation") { put("p_studio_id", studioId); put("p_booking_id", bookingId) }

    suspend fun messages(conversationId: String): List<ChatMessage> = mapped {
        client.from("messages").select {
            filter { eq("conversation_id", conversationId) }
            order("created_at", Order.ASCENDING)
            limit(500)
        }.decodeList()
    }

    @Serializable
    private data class NewMessage(val conversationId: String, val senderId: String, val kind: MessageKind, val body: String)

    suspend fun sendMessage(conversationId: String, body: String): ChatMessage {
        val message = NewMessage(conversationId, userId(), MessageKind.Text, body.trim())
        return mapped { client.from("messages").insert(message) { select() }.decodeSingle() }
    }

    /** Studio → artist: starts (or continues) a conversation. New artists get it as a message request. */
    suspend fun startConversation(artistId: String, body: String): Conversation =
        rpc("studio_start_conversation") { put("p_artist_id", artistId); put("p_body", body) }

    suspend fun respondToMessageRequest(conversationId: String, accept: Boolean): Conversation =
        rpc("respond_message_request") { put("p_conversation_id", conversationId); put("p_accept", accept) }

    /** Artists a studio can message. An empty query returns artists who booked the studio. */
    suspend fun searchArtists(query: String): List<ArtistSearchResult> = rpc("search_artists") { put("p_query", query) }

    /** Live stream of new messages in a conversation. */
    fun messageStream(conversationId: String): Flow<ChatMessage> {
        val id = conversationId.lowercase()
        val channel = client.channel("messages-$id")
        return channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "messages"
            filter("conversation_id", FilterOperator.EQ, id)
        }
            .onStart { channel.subscribe() }
            .mapNotNull { runCatching { it.decodeRecord<ChatMessage>() }.getOrNull() }
            .onCompletion { runCatching { client.realtime.removeChannel(channel) } }
    }

    // MARK: Promotions

    suspend fun promotions(studioId: String): List<StudioPromotion> = mapped {
        client.from("studio_promotions").select { filter { eq("studio_id", studioId) }; order("created_at", Order.DESCENDING) }.decodeList()
    }

    // MARK: Artist ratings

    suspend fun reviewArtist(bookingId: String, rating: Int, text: String): ArtistReview =
        rpc("review_artist") { put("p_booking_id", bookingId); put("p_rating", rating); put("p_text", text) }

    suspend fun artistReviews(artistId: String): List<ArtistReview> = mapped {
        client.from("artist_reviews").select {
            filter { eq("artist_id", artistId) }
            order("created_at", Order.DESCENDING)
            limit(50)
        }.decodeList()
    }

    suspend fun artistReview(bookingId: String): ArtistReview? = mapped {
        client.from("artist_reviews").select { filter { eq("booking_id", bookingId) }; limit(1) }.decodeList<ArtistReview>().firstOrNull()
    }

    // MARK: Studio ↔ artist profile

    /** Accepted connection for a studio (or pending, for its owner). */
    suspend fun studioArtistLink(studioId: String): StudioArtistLink? = mapped {
        client.from("studio_artist_links").select { filter { eq("studio_id", studioId) }; limit(1) }.decodeList<StudioArtistLink>().firstOrNull()
    }

    /** Connections that involve this artist (accepted, and pending ones for the artist). */
    suspend fun artistStudioLinks(artistId: String): List<StudioArtistLink> = mapped {
        client.from("studio_artist_links").select { filter { eq("artist_id", artistId) } }.decodeList()
    }

    suspend fun requestStudioArtistLink(artistId: String): StudioArtistLink =
        rpc("request_studio_artist_link") { put("p_artist_id", artistId) }

    suspend fun respondStudioArtistLink(studioId: String, accept: Boolean) =
        rpcVoid("respond_studio_artist_link") { put("p_studio_id", studioId); put("p_accept", accept) }

    suspend fun removeStudioArtistLink(studioId: String) = rpcVoid("remove_studio_artist_link") { put("p_studio_id", studioId) }

    // MARK: Blocking

    suspend fun conversationBlockState(conversationId: String): BlockState =
        BlockState.from(rpc<String>("conversation_block_state") { put("p_conversation_id", conversationId) })

    suspend fun setConversationBlock(conversationId: String, blocked: Boolean): BlockState =
        BlockState.from(rpc<String>("set_conversation_block") { put("p_conversation_id", conversationId); put("p_blocked", blocked) })

    suspend fun blockUser(id: String) = rpcVoid("block_user") { put("p_user_id", id) }
    suspend fun blockStudio(id: String) = rpcVoid("block_studio") { put("p_studio_id", id) }
    suspend fun unblockUser(id: String) = rpcVoid("unblock_user") { put("p_user_id", id) }
    suspend fun blockedUsers(): List<BlockedUser> = rpc("my_blocked_users")

    // MARK: Rating disputes, moderation, changelog, invoices

    suspend fun disputeRating(kind: RatingKind, reviewId: String, reason: String) =
        rpcVoid("dispute_rating") { put("p_review_type", kind.raw); put("p_review_id", reviewId); put("p_reason", reason) }

    suspend fun unacknowledgedWarnings(): List<ModerationWarning> {
        val all: List<ModerationWarning> = mapped {
            client.from("moderation_actions").select(io.github.jan.supabase.postgrest.query.Columns.list("id", "reason", "created_at", "acknowledged_at")) {
                filter { eq("action", "warning") }
                order("created_at", Order.ASCENDING)
                limit(50)
            }.decodeList()
        }
        return all.filter { it.acknowledgedAt == null }
    }

    suspend fun acknowledgeWarning(id: String) = rpcVoid("acknowledge_warning") { put("p_id", id) }

    suspend fun changelog(): List<ChangelogEntry> = mapped {
        client.from("app_changelog").select { order("published_at", Order.DESCENDING); limit(30) }.decodeList()
    }

    /** The terms version everyone must have accepted (the admin bumps it with a legal update). */
    suspend fun currentTermsVersion(): String = rpc("current_terms_version")

    suspend fun feeInvoices(studioId: String): List<FeeInvoice> = mapped {
        client.from("studio_fee_invoices").select { filter { eq("studio_id", studioId) }; order("created_at", Order.DESCENDING) }.decodeList()
    }

    // MARK: Support

    suspend fun supportTickets(): List<SupportTicket> = mapped {
        client.from("support_tickets").select { order("last_message_at", Order.DESCENDING) }.decodeList()
    }

    suspend fun createSupportTicket(subject: String, category: SupportCategory, body: String, bookingId: String?): SupportTicket =
        rpc("create_support_ticket") {
            put("p_subject", subject.trim())
            put("p_category", PostgresJson.encodeToJsonElement(SupportCategory.serializer(), category))
            put("p_body", body)
            put("p_booking_id", bookingId)
        }

    suspend fun supportMessages(ticketId: String): List<SupportMessage> = mapped {
        client.from("support_messages").select { filter { eq("ticket_id", ticketId) }; order("created_at", Order.ASCENDING) }.decodeList()
    }

    suspend fun sendSupportMessage(ticketId: String, body: String): SupportMessage =
        rpc("send_support_message") { put("p_ticket_id", ticketId); put("p_body", body) }

    suspend fun markSupportTicketRead(id: String) = rpcVoid("mark_support_ticket_read") { put("p_ticket_id", id) }

    suspend fun rateSupportTicket(id: String, rating: Int, comment: String): SupportTicket =
        rpc("rate_support_ticket") { put("p_ticket_id", id); put("p_rating", rating); put("p_comment", comment) }

    suspend fun closeSupportTicket(id: String): SupportTicket =
        rpc("set_support_ticket_status") { put("p_ticket_id", id); put("p_status", "closed") }

    suspend fun markConversationRead(id: String) = rpcVoid("mark_conversation_read") { put("p_conversation_id", id) }

    // MARK: Reviews & moderation

    suspend fun reviews(studioId: String): List<Review> = mapped {
        client.from("reviews").select {
            filter {
                eq("studio_id", studioId)
                eq("is_hidden", false)
            }
            order("created_at", Order.DESCENDING)
        }.decodeList()
    }

    @Serializable
    private data class NewReview(
        val bookingId: String, val studioId: String, val artistId: String, val artistName: String,
        val rating: Int, val facilitiesRating: Int, val experienceRating: Int, val engineerRating: Int?, val text: String,
    )

    suspend fun submitReview(review: Review): Review {
        val row = NewReview(review.bookingId, review.studioId, userId(), review.artistName, review.rating,
            review.facilitiesRating, review.experienceRating, review.engineerRating, review.text)
        return mapped { client.from("reviews").insert(row) { select() }.decodeSingle() }
    }

    suspend fun replyToReview(id: String, reply: String): Review = rpc("reply_to_review") { put("p_review_id", id); put("p_reply", reply) }

    @Serializable
    private data class NewReport(val reporterId: String, val targetType: ReportTarget, val targetId: String, val reason: ReportReason, val details: String)

    suspend fun report(target: ReportTarget, targetId: String, reason: ReportReason, details: String) {
        val row = NewReport(userId(), target, targetId, reason, details)
        mapped { client.from("reports").insert(row) }
    }

    // MARK: Notifications

    suspend fun notifications(): List<AppNotification> = mapped {
        client.from("notifications").select { order("created_at", Order.DESCENDING); limit(100) }.decodeList()
    }

    suspend fun markNotificationRead(id: String) {
        mapped { client.from("notifications").update({ set("is_read", true) }) { filter { eq("id", id) } } }
    }

    suspend fun markAllNotificationsRead() {
        val id = userId()
        mapped {
            client.from("notifications").update({ set("is_read", true) }) {
                filter {
                    eq("user_id", id)
                    eq("is_read", false)
                }
            }
        }
    }

    suspend fun deleteNotification(id: String) {
        mapped { client.from("notifications").delete { filter { eq("id", id) } } }
    }

    suspend fun deleteAllNotifications() {
        val id = userId()
        mapped { client.from("notifications").delete { filter { eq("user_id", id) } } }
    }

    @Serializable
    private data class DeviceToken(val token: String, val userId: String, val platform: String)

    suspend fun registerPushToken(token: String) {
        val row = DeviceToken(token, userId(), "android")
        mapped { client.from("device_tokens").upsert(row) { onConflict = "token" } }
    }

    val currentUserId: String? get() = client.auth.currentUserOrNull()?.id

    companion object {
        const val REDIRECT_SCHEME = "easysesh"
        const val REDIRECT_HOST = "auth-callback"
        const val REDIRECT_URL = "easysesh://auth-callback"
    }
}

/** kotlinx JsonObjectBuilder helpers for nullable values (JSON null like AnyJSON.null on iOS). */
private fun JsonObjectBuilder.put(key: String, value: String?) { put(key, value?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: JsonNull) }
private fun JsonObjectBuilder.put(key: String, value: Double?) { put(key, value?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: JsonNull) }
