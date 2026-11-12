package com.shellx.app.ui.settings

import android.content.Context
import android.content.Intent
import java.io.IOException
import java.io.InputStream

/** The notices file shellx-android/scripts/generate-licences.py writes (plan 3H). */
const val LICENCES_ASSET = "licenses/third_party_licenses.txt"

/** The longest block the Licenses list shows as one item; longer licence texts are cut so the list stays lazy. */
const val MAX_BLOCK_LINES = 40

/** What Settings › About › Licenses does on Android: opens the open-source licence notices (plan 3H). */
fun openLicences(context: Context) {
    context.startActivity(Intent(context, LicencesActivity::class.java))
}

/** The notices text, or null when the asset cannot be read. */
fun readLicenceNotices(open: () -> InputStream): String? =
    try {
        open().bufferedReader().use { it.readText() }
    } catch (_: IOException) {
        null
    }

/** The notices as list items: paragraphs, with a paragraph of more than [MAX_BLOCK_LINES] lines cut into pieces. */
fun licenceBlocks(text: String): List<String> =
    text.replace("\r\n", "\n").split(Regex("\n{2,}"))
        .filter { it.isNotBlank() }
        .flatMap { paragraph -> paragraph.trimEnd().lines().chunked(MAX_BLOCK_LINES).map { it.joinToString("\n") } }
