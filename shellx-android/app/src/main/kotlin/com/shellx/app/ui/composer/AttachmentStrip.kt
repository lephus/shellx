package com.shellx.app.ui.composer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.link.core.AttachmentKind
import java.io.ByteArrayInputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max

/**
 * The attachments waiting in the composer (`AttachmentStrip.swift`): a row of 56 dp tiles above the field, a photo as
 * its thumbnail and a file as an icon over its name, then a spinner tile for each pick still being read. Each tile has
 * an ✕: on an attachment it takes it out ([onRemove], off while [locked]); on a spinner it stops that read
 * ([cancelLoading]). The whole row dims while [locked].
 *
 * [spinner] draws a pick still being read (render tests pass a still one).
 */
@Composable
fun AttachmentStrip(
    attachments: List<OutgoingAttachment>,
    onRemove: (String) -> Unit,
    locked: Boolean,
    loading: List<String>,
    cancelLoading: (String) -> Unit,
    spinner: @Composable () -> Unit = { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) },
) {
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .alpha(if (locked) 0.6f else 1f)
            .testTag("composer.attachments")
            // Room for the ✕ buttons, which stand out of the tiles' corners.
            .padding(top = 12.dp, end = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        for (attachment in attachments) {
            Box {
                AttachmentTile(attachment)
                RemoveButton(
                    stringResource(R.string.composer_attachment_remove, attachment.name), enabled = !locked,
                    modifier = Modifier.align(Alignment.TopEnd),
                ) { onRemove(attachment.id) }
            }
        }
        for (id in loading) {
            val label = stringResource(R.string.composer_attach_loading)
            Box {
                Box(
                    Modifier
                        .size(AttachmentStrip.TILE_SIDE)
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                        .semantics { contentDescription = label },
                    contentAlignment = Alignment.Center,
                ) { spinner() }
                RemoveButton(stringResource(R.string.composer_attach_cancel_loading), enabled = true, modifier = Modifier.align(Alignment.TopEnd)) {
                    cancelLoading(id)
                }
            }
        }
    }
}

object AttachmentStrip {
    val TILE_SIDE: Dp = 56.dp
}

@Composable
private fun AttachmentTile(attachment: OutgoingAttachment) {
    val thumbnail by produceState(AttachmentThumbnails.cached(attachment), attachment.id) {
        if (value == null && attachment.kind == AttachmentKind.IMAGE) {
            value = withContext(Dispatchers.Default) { AttachmentThumbnails.image(attachment) }
        }
    }
    val image = thumbnail
    Box(
        Modifier
            .size(AttachmentStrip.TILE_SIDE)
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clearAndSetSemantics { contentDescription = attachment.name },
        contentAlignment = Alignment.Center,
    ) {
        if (attachment.kind == AttachmentKind.IMAGE && image != null) {
            Image(image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(AttachmentStrip.TILE_SIDE))
        } else {
            Column(Modifier.padding(horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    if (attachment.kind == AttachmentKind.IMAGE) Icons.Outlined.Image else Icons.Outlined.Description,
                    contentDescription = null,
                    tint = ShellXTheme.colors.accentText,
                    modifier = Modifier.size(22.dp),
                )
                Text(
                    attachment.name,
                    fontSize = 9.sp,
                    lineHeight = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
            }
        }
    }
}

/** The ✕ standing out of a tile's top-end corner: a 20 dp disc in a 40 dp touch target. */
@Composable
private fun RemoveButton(label: String, enabled: Boolean, modifier: Modifier, action: () -> Unit) {
    Box(
        modifier
            .offset(x = 14.dp, y = (-14).dp)
            .size(40.dp)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = null, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(20.dp).background(MaterialTheme.colorScheme.onSurfaceVariant, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Close, contentDescription = null, tint = MaterialTheme.colorScheme.surface, modifier = Modifier.size(12.dp))
        }
    }
}

/**
 * Small images of the photos in the composer, decoded with `inSampleSize` so the long side is at least
 * [MAX_PIXEL_SIZE] (never the full image in memory), turned upright by their EXIF orientation, and kept in an LRU
 * cache of 32 by attachment id. Display only: what is sent is untouched.
 */
object AttachmentThumbnails {
    const val MAX_PIXEL_SIZE = 200
    private val cache = LruCache<String, ImageBitmap>(32)

    /** The thumbnail already made for [attachment], without decoding anything. */
    fun cached(attachment: OutgoingAttachment): ImageBitmap? = cache.get(attachment.id)

    /** The thumbnail of [attachment]; decodes it the first time (call it off the main thread). Null when the bytes are
     *  no image. */
    fun image(attachment: OutgoingAttachment): ImageBitmap? {
        cache.get(attachment.id)?.let { return it }
        val data = attachment.data
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val longSide = max(bounds.outWidth, bounds.outHeight)
        if (longSide <= 0) return null
        var sample = 1
        while (longSide / (sample * 2) >= MAX_PIXEL_SIZE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val degrees = rotation(data)
        val upright = if (degrees == 0) {
            decoded
        } else {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postRotate(degrees.toFloat()) }, true)
        }
        return upright.asImageBitmap().also { cache.put(attachment.id, it) }
    }

    /** How far the photo's EXIF orientation turns it (0 without one). */
    private fun rotation(data: ByteArray): Int = try {
        when (ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (e: Exception) {
        0
    }
}
