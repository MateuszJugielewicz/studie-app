package com.easysesh.app.services

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.easysesh.app.core.GeoPoint
import com.easysesh.app.model.Studio
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/** The phone's location for "studios near you" and check-in. */
class LocationService(private val context: Context) {
    private val client = LocationServices.getFusedLocationProviderClient(context)

    var location by mutableStateOf<GeoPoint?>(null)
        private set
    var cityName by mutableStateOf<String?>(null)
        private set
    var isAuthorized by mutableStateOf(hasPermission())
        private set

    /** Set by MainActivity: shows the system permission dialog. */
    var permissionRequester: (() -> Unit)? = null

    val effectiveLocation: GeoPoint get() = location ?: FALLBACK

    private fun hasPermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun requestPermission() {
        if (hasPermission()) refresh() else permissionRequester?.invoke()
    }

    /** Called by MainActivity after the permission dialog closes. */
    fun onPermissionResult() {
        isAuthorized = hasPermission()
        if (isAuthorized) refresh()
    }

    @SuppressLint("MissingPermission")
    fun refresh() {
        isAuthorized = hasPermission()
        if (!isAuthorized) return
        client.lastLocation.addOnSuccessListener { last -> last?.let { update(GeoPoint(it.latitude, it.longitude)) } }
        client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, CancellationTokenSource().token)
            .addOnSuccessListener { current -> current?.let { update(GeoPoint(it.latitude, it.longitude)) } }
    }

    private fun update(point: GeoPoint) {
        location = point
        reverseGeocode(point)
    }

    /** A current position for check-in: asks for one and waits up to 8 seconds. */
    @SuppressLint("MissingPermission")
    suspend fun freshLocation(): GeoPoint? {
        if (!hasPermission()) return null
        return withTimeoutOrNull(8_000) {
            suspendCancellableCoroutine { continuation ->
                val token = CancellationTokenSource()
                client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, token.token)
                    .addOnSuccessListener { continuation.resume(it?.let { l -> GeoPoint(l.latitude, l.longitude) }) }
                    .addOnFailureListener { continuation.resume(null) }
                continuation.invokeOnCancellation { token.cancel() }
            }
        } ?: location
    }

    @Suppress("DEPRECATION")
    private fun reverseGeocode(point: GeoPoint) {
        if (!Geocoder.isPresent()) return
        val geocoder = Geocoder(context, Locale.getDefault())
        if (Build.VERSION.SDK_INT >= 33) {
            geocoder.getFromLocation(point.latitude, point.longitude, 1) { results -> cityName = results.firstOrNull()?.locality }
        } else {
            Thread { cityName = runCatching { geocoder.getFromLocation(point.latitude, point.longitude, 1)?.firstOrNull()?.locality }.getOrNull() }.start()
        }
    }

    companion object {
        /** Used when location is denied so the app still shows something sensible. */
        val FALLBACK = GeoPoint(37.9838, 23.7275) // Athens

        /** Resolves a typed address to coordinates (used by studio onboarding). */
        @Suppress("DEPRECATION")
        suspend fun geocode(context: Context, address: String): GeoPoint? = withContext(Dispatchers.IO) {
            if (!Geocoder.isPresent()) return@withContext null
            runCatching { Geocoder(context, Locale.getDefault()).getFromLocationName(address, 1)?.firstOrNull() }
                .getOrNull()?.let { GeoPoint(it.latitude, it.longitude) }
        }

        /** Opens turn-by-turn directions in the phone's maps app. */
        fun openDirections(context: Context, studio: Studio) {
            val uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${studio.latitude},${studio.longitude}")
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=${studio.latitude},${studio.longitude}"))
            val fallback = Intent(Intent.ACTION_VIEW, uri)
            runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                .onFailure { runCatching { context.startActivity(fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
        }
    }
}
