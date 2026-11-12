package com.shellx.app.ui.settings

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/**
 * Shows the open-source licence notices bundled in assets/licenses/third_party_licenses.txt, which
 * shellx-android/scripts/generate-licences.py writes from the lockfile and the libraries' POMs (plan 3H). System Back
 * closes it.
 */
class LicencesActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ShellXTheme {
                LicencesScreen(assets.open("licenses/third_party_licenses.txt").bufferedReader().use { it.readText() })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicencesScreen(text: String) {
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_about_license)) }) }) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(text.split("\n\n").filter { it.isNotBlank() }) { block ->
                Text(block.trim(), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
