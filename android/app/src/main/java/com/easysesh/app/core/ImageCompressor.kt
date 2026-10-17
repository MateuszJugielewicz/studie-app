package com.easysesh.app.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/** Shrinks a picked photo to a JPEG no larger than `maxDimension` on its longest side. */
object ImageCompressor {
    fun jpeg(context: Context, uri: Uri, maxDimension: Int, quality: Int = 80): ByteArray? {
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= 28) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } else {
                context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
            }
        }.getOrNull() ?: return null
        val scale = min(1f, maxDimension.toFloat() / max(bitmap.width, bitmap.height))
        val resized = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
        return ByteArrayOutputStream().use { out ->
            resized.compress(Bitmap.CompressFormat.JPEG, quality, out)
            out.toByteArray()
        }
    }
}
