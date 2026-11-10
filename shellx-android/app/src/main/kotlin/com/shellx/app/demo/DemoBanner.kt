package com.shellx.app.demo

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/**
 * The window's frame (1C's `DemoRootView`): while the [demo] runs, the "Demo · Exit" banner ([DemoBanner]) under the
 * status bar, above [content].
 */
@Composable
fun DemoFrame(demo: Boolean, exit: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        if (demo) DemoBanner(exit, Modifier.windowInsetsPadding(WindowInsets.statusBars))
        Box(Modifier.weight(1f).then(if (demo) Modifier.consumeWindowInsets(WindowInsets.statusBars) else Modifier)) {
            content()
        }
    }
}

/** The "Demo · Exit" banner over the demo account's screens (1C's `DemoBanner`). */
@Composable
fun DemoBanner(exit: () -> Unit, modifier: Modifier = Modifier) {
    val accentText = ShellXTheme.colors.accentText
    val label = stringResource(R.string.demo_banner_label)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(accentText.copy(alpha = 0.14f))
            .padding(horizontal = 16.dp)
            .testTag("demo.banner"),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.demo_banner_title),
            style = MaterialTheme.typography.titleSmall,
            color = accentText,
            modifier = Modifier.semantics { contentDescription = label },
        )
        Text(text = "·", style = MaterialTheme.typography.titleSmall, color = accentText, modifier = Modifier.clearAndSetSemantics {})
        TextButton(onClick = exit, modifier = Modifier.testTag("demo.exit")) {
            Text(stringResource(R.string.demo_banner_exit), style = MaterialTheme.typography.titleSmall, color = accentText)
        }
    }
}
