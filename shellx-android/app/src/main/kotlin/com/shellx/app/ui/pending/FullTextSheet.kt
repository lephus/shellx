package com.shellx.app.ui.pending

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.topBarHeight
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.pending.previewFields
import com.shellx.core.pending.previewMayBeCut
import com.shellx.core.pending.previewText
import com.shellx.link.core.PendingItem

/**
 * Everything a request's preview holds, scrolling ("Show more" on a card; `FullTextSheet.swift`): each field of a
 * tool's input, or the text as it came. Display only; selectable for copying. The host puts it in a bottom sheet.
 */
@Composable
fun FullTextSheet(item: PendingItem, close: () -> Unit) {
    val title = item.toolName?.takeIf { it.isNotEmpty() } ?: stringResource(R.string.pending_full_text_title)
    val raw = item.toolInputPreview ?: item.previewText ?: ""
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLow)) {
        SheetTopBar(title, close)
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) { Fields(item, raw) }
    }
}

@Composable
private fun Fields(item: PendingItem, raw: String) {
    SelectionContainer {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            val fields = item.previewFields
            if (fields != null) {
                for ((key, value) in fields) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            key,
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Monospaced(value)
                    }
                }
            } else {
                Monospaced(raw)
            }
            if (PendingItem.previewMayBeCut(raw)) CutNotice()
        }
    }
}

/** A sheet's top bar: "Close" (tag `pending.close`) at the start, the title in the middle. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SheetTopBar(title: String, close: () -> Unit) {
    CenterAlignedTopAppBar(
        title = { Text(title, maxLines = 1) },
        navigationIcon = {
            TextButton(onClick = close, modifier = Modifier.testTag("pending.close")) {
                Text(stringResource(R.string.common_close), color = ShellXTheme.colors.accentText)
            }
        },
        expandedHeight = topBarHeight(),
        windowInsets = WindowInsets(0),
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
    )
}

@Composable
private fun Monospaced(text: String) {
    Text(
        text,
        modifier = Modifier
            .fillMaxWidth()
            .sheetCard(RoundedCornerShape(10.dp))
            .padding(12.dp),
        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
    )
}
