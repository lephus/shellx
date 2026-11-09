package com.shellx.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.shellx.app.ui.LaunchView
import com.shellx.app.ui.theme.ShellXTheme

/** The only activity, and the launcher. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { ShellXTheme { LaunchView() } }
    }
}
