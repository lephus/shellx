package com.shellx.app.ui.machines

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.components.ActionRow
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.components.MessageDialog
import com.shellx.app.ui.components.RowActionKind
import com.shellx.app.ui.components.RowActions
import com.shellx.app.ui.components.menuAction
import com.shellx.app.ui.components.shellXCard
import com.shellx.app.ui.components.swipeAction
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.link.MachineLinkState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One row's data, copied from a `MachineModel`. */
data class MachineListItem(val id: String, val name: String, val state: MachineLinkState) {
    /** "Make Default" is offered unless the Mac is already the default, or cannot take messages until it is paired
     *  again (revoked, key changed). */
    fun offersMakeDefault(defaultId: String?): Boolean = id != defaultId && state.canBeDefault
}

/**
 * The unpairs under way and the last one that failed, kept across a recreated page (carry 3D-3): the unpair itself
 * runs where the caller put it (the hub's scope); this only waits for it. Main-confined.
 */
internal class MachineListProgress : ViewModel() {
    private val _working = MutableStateFlow<Set<String>>(emptySet())
    val working: StateFlow<Set<String>> = _working.asStateFlow()

    /** The name of the Mac whose unpair failed, until the message is dismissed. */
    private val _failed = MutableStateFlow<String?>(null)
    val failed: StateFlow<String?> = _failed.asStateFlow()

    /** Unpairs [item] once: an id already under way sends nothing. */
    fun unpair(item: MachineListItem, unpair: suspend (String) -> Unit) {
        if (item.id in _working.value) return
        _working.update { it + item.id }
        viewModelScope.launch {
            try {
                unpair(item.id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _failed.value = item.name
            } finally {
                _working.update { it - item.id }
            }
        }
    }

    fun dismissFailure() {
        _failed.value = null
    }
}

/**
 * The list of paired Macs with its actions (MachineList in `MachinesView.swift`), from plain values. A swipe runs
 * Unpair (asks first) or Remove; a long press offers Make Default, Pair Again and Unpair as the Mac allows. Removing a
 * Mac that already removed this phone does not ask.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachineList(
    items: List<MachineListItem>,
    defaultId: String?,
    makeDefault: (String) -> Unit,
    unpair: suspend (String) -> Unit,
    pair: () -> Unit,
    back: () -> Unit,
) {
    val progress = viewModel { MachineListProgress() }
    val working by progress.working.collectAsStateWithLifecycle()
    val failedName by progress.failed.collectAsStateWithLifecycle()
    var confirmingId by rememberSaveable { mutableStateOf<String?>(null) }
    val confirming = items.firstOrNull { it.id == confirmingId }
    val unpairNow: (MachineListItem) -> Unit = { progress.unpair(it, unpair) }
    val background = MaterialTheme.colorScheme.background

    Scaffold(
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.machines_title)) },
                navigationIcon = {
                    IconButton(onClick = back) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                actions = {
                    IconButton(onClick = pair, modifier = Modifier.testTag("machines.pair")) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.pairing_title))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        ) {
            item(key = "macs") {
                Column(Modifier.fillMaxWidth().shellXCard(RoundedCornerShape(12.dp))) {
                    items.forEachIndexed { index, item ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp))
                        MachineItem(
                            item = item,
                            isDefault = item.id == defaultId,
                            offersMakeDefault = item.offersMakeDefault(defaultId),
                            enabled = item.id !in working,
                            confirm = { confirmingId = item.id },
                            unpairNow = { unpairNow(item) },
                            makeDefault = { makeDefault(item.id) },
                            pair = pair,
                        )
                    }
                }
            }
            item(key = "footer") {
                Text(
                    text = stringResource(R.string.machines_footer),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

    if (confirming != null) {
        ConfirmDialog(
            title = stringResource(R.string.machines_unpair_title, confirming.name),
            text = stringResource(R.string.machines_unpair_message),
            confirmLabel = stringResource(R.string.machines_unpair),
            onConfirm = { unpairNow(confirming) },
            onDismiss = { confirmingId = null },
        )
    }
    failedName?.let { name ->
        MessageDialog(
            title = stringResource(R.string.machines_unpair_failed_title),
            text = stringResource(R.string.machines_unpair_failed_message, name),
            onDismiss = progress::dismissFailure,
        )
    }
}

@Composable
private fun MachineItem(
    item: MachineListItem,
    isDefault: Boolean,
    offersMakeDefault: Boolean,
    enabled: Boolean,
    confirm: () -> Unit,
    unpairNow: () -> Unit,
    makeDefault: () -> Unit,
    pair: () -> Unit,
) {
    val plan = RowActions.machine(item.state, offersMakeDefault)
    val run: (RowActionKind) -> () -> Unit = { kind ->
        when (kind) {
            RowActionKind.UNPAIR -> confirm
            RowActionKind.REMOVE_MAC -> unpairNow
            RowActionKind.MAKE_DEFAULT -> makeDefault
            RowActionKind.PAIR_AGAIN -> pair
            else -> ({})
        }
    }
    ActionRow(
        swipe = plan.swipe?.let { it.swipeAction(run(it)) },
        menu = plan.menu.map { it.menuAction(run(it)) },
        onClick = null,
        onClickLabel = null,
        modifier = Modifier.testTag("machines.row.${item.id}"),
        enabled = enabled,
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
            MachineRow(item.name, item.state, isDefault, pairAgain = pair, remove = unpairNow)
        }
    }
}

/** Route `machines` (`MachinesView.swift`): fed by the hub; an unpair runs in the hub's scope and the page awaits it. */
@Composable
fun MachinesView(scope: SignedInScope, navigator: ShellXNavigator) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    MachineList(
        items = hub.machines.map { MachineListItem(it.id, it.name, it.state) },
        defaultId = hub.defaultMachineId,
        makeDefault = { scope.hub.defaultMachineId = it },
        unpair = { id -> scope.hub.scope.async { scope.hub.unpair(id) }.await() },
        pair = navigator::openPairing,
        back = navigator::back,
    )
}
