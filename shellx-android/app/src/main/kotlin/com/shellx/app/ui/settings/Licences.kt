package com.shellx.app.ui.settings

import android.content.Context
import android.content.Intent

/** What Settings › About › Licenses does on Android: opens the open-source licence notices (plan 3H). */
fun openLicences(context: Context) {
    context.startActivity(Intent(context, LicencesActivity::class.java))
}
