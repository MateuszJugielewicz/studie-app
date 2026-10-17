package com.easysesh.app.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// MARK: Navigation stack (iOS NavigationStack / NavigationLink)

class Navigator {
    data class Entry(val id: Long, val content: @Composable () -> Unit)

    val stack = mutableStateListOf<Entry>()
    private var nextId = 0L

    fun push(content: @Composable () -> Unit) {
        stack.add(Entry(nextId++, content))
    }

    fun pop() {
        if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
    }

    fun popToRoot() = stack.clear()
}

val LocalNavigator = compositionLocalOf<Navigator?> { null }

/** Closes the current screen: pops it, or closes the sheet it's in (iOS @Environment(\.dismiss)). */
val LocalDismiss = compositionLocalOf<() -> Unit> { {} }

/** Whether the current screen was pushed (shows a back button). */
val LocalIsPushed = compositionLocalOf { false }

/**
 * A navigation stack. Pushed screens stay composed underneath (like iOS keeps them alive), so
 * going back keeps scroll positions and loaded data.
 */
@Composable
fun NavigationStack(navigator: Navigator = remember { Navigator() }, root: @Composable () -> Unit) {
    val outerDismiss = LocalDismiss.current
    BackHandler(enabled = navigator.stack.isNotEmpty()) { navigator.pop() }
    CompositionLocalProvider(LocalNavigator provides navigator) {
        Box(Modifier.fillMaxSize()) {
            val top = navigator.stack.size
            Layer(visible = top == 0) {
                CompositionLocalProvider(LocalIsPushed provides false, LocalDismiss provides outerDismiss) { root() }
            }
            navigator.stack.forEachIndexed { index, entry ->
                key(entry.id) {
                    val offset = remember { Animatable(1f) }
                    LaunchedEffect(Unit) { offset.animateTo(0f, tween(300, easing = FastOutSlowInEasing)) }
                    Layer(visible = index == top - 1, modifier = Modifier.graphicsLayer { translationX = offset.value * size.width }) {
                        CompositionLocalProvider(LocalIsPushed provides true, LocalDismiss provides { navigator.pop() }) { entry.content() }
                    }
                }
            }
        }
    }
}

@Composable
private fun Layer(visible: Boolean, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxSize()
            .graphicsLayer { alpha = if (visible) 1f else 0f }
            // Catches touches so screens underneath don't get them.
            .then(if (visible) Modifier.pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } } else Modifier),
    ) { content() }
}

/** Pushes `destination` when tapped (iOS NavigationLink). */
@Composable
fun NavLink(destination: @Composable () -> Unit, modifier: Modifier = Modifier, label: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    Box(modifier.pressable { navigator?.push(destination) }) { label() }
}

// MARK: Screens

/**
 * A pushed screen with an inline title, a round glass back button and toolbar actions
 * (iOS navigationTitle + toolbar). `grouped` gives the aurora + frosted list look.
 */
@Composable
fun NavScreen(
    title: String,
    modifier: Modifier = Modifier,
    translateTitle: Boolean = true,
    leading: (@Composable RowScope.() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    titleContent: (@Composable () -> Unit)? = null,
    bottomBar: (@Composable () -> Unit)? = null,
    scrollable: Boolean = true,
    auroraHeight: Dp = 340.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val dismiss = LocalDismiss.current
    val isPushed = LocalIsPushed.current
    Column(modifier.fillMaxSize().auroraBackground(auroraHeight, intensity = 0.8f)) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 52.dp).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(Modifier.widthIn(min = 72.dp), verticalAlignment = Alignment.CenterVertically) {
                if (leading != null) leading()
                else if (isPushed) BackButton(dismiss)
            }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                if (titleContent != null) titleContent()
                else Txt(if (translateTitle) tr(title) else title, style = Type.system(17, FontWeight.Bold), maxLines = 1, align = TextAlign.Center)
            }
            Row(Modifier.widthIn(min = 72.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically, content = actions)
        }
        val body = Modifier.weight(1f).fillMaxWidth()
        if (scrollable) {
            Column(body.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 28.dp, top = 4.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
        } else {
            Column(body, content = content)
        }
        if (bottomBar != null) bottomBar()
    }
}

@Composable
fun BackButton(onClick: () -> Unit) {
    Box(
        Modifier
            .size(34.dp)
            .background(if (Theme.colors.isDark) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.06f), CircleShape)
            .border(0.8.dp, if (Theme.colors.isDark) Color.White.copy(alpha = 0.22f) else Color.Black.copy(alpha = 0.1f), CircleShape)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Sym("chevron.left", size = 22.dp) }
}

/** Toolbar text action (iOS ToolbarItem Button). */
@Composable
fun ToolbarButton(title: String, enabled: Boolean = true, bold: Boolean = false, color: Color = Theme.accent, onClick: () -> Unit) {
    Txt(
        tr(title),
        Modifier.clip(RoundedCornerShape(10.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp, vertical = 6.dp),
        style = Type.body.copy(fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal),
        color = if (enabled) color else Theme.secondary,
    )
}

private class CollapseState { var value by mutableStateOf(0f) }

/**
 * Tab root screen: a large title that fades away while scrolling and hands over to a slim glass
 * bar with a neon hairline (iOS EasySeshScreen).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EasySeshScreen(
    title: String,
    eyebrow: String? = null,
    refresh: suspend () -> Unit,
    trailing: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val collapse by remember {
        derivedStateOf {
            val px = with(density) { 24.dp.toPx() }
            val range = with(density) { 44.dp.toPx() }
            (((scroll.value - px) / range).coerceIn(0f, 1f) * 10).roundToInt() / 10f
        }
    }
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    val animated by animateFloatAsState(collapse, tween(180), label = "collapse")
    Box(Modifier.fillMaxSize().auroraBackground(420.dp)) {
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; runCatching { refresh() }; refreshing = false } },
            modifier = Modifier.fillMaxSize(),
        ) {
            Column(
                Modifier.fillMaxSize().verticalScroll(scroll).statusBarsPadding().padding(horizontal = 16.dp).padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(top = 12.dp).graphicsLayer {
                        alpha = 1 - animated
                        val s = 1 - animated * 0.08f
                        scaleX = s; scaleY = s
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 1f)
                    },
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (eyebrow != null) Eyebrow(eyebrow)
                        GradientText(tr(title), Brush.verticalGradient(listOf(Theme.primary, Theme.primary.copy(alpha = 0.7f))),
                            Type.system(34, FontWeight.ExtraBold).tracking(-0.8f), maxLines = 2)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), content = trailing)
                }
                content()
            }
        }
        // Compact bar that takes over once the large title has scrolled away.
        if (animated > 0.01f) {
            Column(Modifier.fillMaxWidth().graphicsLayer { alpha = animated; translationY = (1 - animated) * -30f }) {
                Row(
                    Modifier.fillMaxWidth().background(Theme.background.copy(alpha = 0.92f)).statusBarsPadding().height(50.dp).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.size(8.dp).neonGlow(Theme.magenta, 6.dp, CircleShape).background(Theme.neon, CircleShape))
                    T(title, Modifier.weight(1f), style = Type.headline, maxLines = 1)
                    Row(Modifier.graphicsLayer { scaleX = 0.85f; scaleY = 0.85f }, horizontalArrangement = Arrangement.spacedBy(8.dp), content = trailing)
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.neon).graphicsLayer { alpha = 0.7f })
            }
        }
    }
}

// MARK: Sheets & dialogs

/** A sheet (iOS `.sheet`), with its own navigation stack inside. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val close: () -> Unit = { scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = Theme.background,
        dragHandle = null,
        contentWindowInsets = { WindowInsets(0) },
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
    ) {
        Box(Modifier.fillMaxWidth().fillMaxSize(0.96f).imePadding()) {
            CompositionLocalProvider(LocalDismiss provides close) {
                NavigationStack { content() }
            }
        }
    }
}

data class DialogAction(val title: String, val destructive: Boolean = false, val translate: Boolean = true, val action: () -> Unit)

/** Action sheet with a title, optional message and buttons, plus Cancel (iOS confirmationDialog). */
@Composable
fun ConfirmDialog(title: String, message: String? = null, actions: List<DialogAction>, onDismiss: () -> Unit, translateTitle: Boolean = true) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Theme.card,
        title = { Txt(if (translateTitle) tr(title) else title, style = Type.headline) },
        text = if (message != null) ({ Txt(message, style = Type.body, color = Theme.secondary) }) else null,
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                actions.forEach { item ->
                    TextButton(onClick = { onDismiss(); item.action() }) {
                        Txt(if (item.translate) tr(item.title) else item.title, style = Type.body.semibold, color = if (item.destructive) Theme.red else Theme.accent)
                    }
                }
                TextButton(onClick = onDismiss) { T("Cancel", style = Type.body, color = Theme.secondary) }
            }
        },
    )
}

// MARK: Segmented control

/** Segmented control in the house style: a glass capsule with a neon pill that slides between options. */
@Composable
fun <T> GlassSegmentedControl(selection: T, options: List<T>, title: (T) -> String, symbol: ((T) -> String)? = null, onSelect: (T) -> Unit) {
    val haptics = LocalHapticFeedback.current
    BoxWithConstraints(
        Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.6f), CircleShape).border(0.8.dp, Theme.colors.glassEdge, CircleShape).padding(4.dp),
    ) {
        val count = options.size.coerceAtLeast(1)
        val itemWidth = (maxWidth - 4.dp * (count - 1)) / count
        val index = options.indexOf(selection).coerceAtLeast(0)
        val x by animateDpAsState((itemWidth + 4.dp) * index, spring(dampingRatio = 0.78f, stiffness = 500f), label = "pill")
        Box(Modifier.offset(x = x).width(itemWidth).height(38.dp).neonGlow(Theme.magenta, 10.dp, CircleShape).background(Theme.neon, CircleShape).border(0.8.dp, Color.White.copy(alpha = 0.25f), CircleShape))
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            options.forEach { option ->
                val selected = option == selection
                Row(
                    Modifier.width(itemWidth).height(38.dp).clip(CircleShape).clickable {
                        if (!selected) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(option)
                    },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val color = if (selected) Color.White else Theme.secondary
                    if (symbol != null) { Sym(symbol(option), size = 15.dp, tint = color); HSpace(6.dp) }
                    T(title(option), style = Type.subheadline.semibold, color = color, maxLines = 1)
                }
            }
        }
    }
}

// MARK: Swipe to delete

/** Swipe a card to the left to delete it (iOS swipeToDelete). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwipeToDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = {
        if (it == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().padding(start = 40.dp), contentAlignment = Alignment.CenterEnd) {
                Box(Modifier.size(56.dp).background(Theme.red, RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                    Sym("trash.fill", size = 20.dp, tint = Color.White)
                }
            }
        },
    ) { content() }
}

// MARK: Floating tab bar

data class TabSpec(val tab: AppTab, val title: String, val symbol: String, val badge: Int = 0)

/**
 * Replaces the system tab bar with a floating glass bar. Tabs are created on first visit and kept
 * alive afterwards. Tapping the tab you're on takes it back to its first screen.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EasySeshTabContainer(
    selection: AppTab,
    onSelect: (AppTab) -> Unit,
    tabs: List<TabSpec>,
    resets: Map<AppTab, Int>,
    tour: TabTour? = null,
    content: @Composable (AppTab) -> Unit,
) {
    val visited = remember { mutableStateMapOf<AppTab, Boolean>() }
    visited[selection] = true
    val tabBounds = remember { mutableStateMapOf<AppTab, androidx.compose.ui.geometry.Rect>() }
    val keyboard = WindowInsets.isImeVisible
    Box(Modifier.fillMaxSize().background(Theme.background)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                tabs.forEach { spec ->
                    if (spec.tab == selection || visited[spec.tab] == true) {
                        key(spec.tab, resets[spec.tab] ?: 0) {
                            Layer(visible = spec.tab == selection) { content(spec.tab) }
                        }
                    }
                }
            }
            AnimatedVisibility(!keyboard, enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
                Box(Modifier.fillMaxWidth().background(Theme.background).navigationBarsPadding().padding(top = 6.dp)) {
                    EasySeshTabBar(selection, tabs, onSelect, onBounds = { tab, rect -> tabBounds[tab] = rect })
                }
            }
        }
        if (tour != null) TourOverlay(tour, tabBounds, onSelect)
    }
}

@Composable
private fun EasySeshTabBar(
    selection: AppTab,
    tabs: List<TabSpec>,
    onSelect: (AppTab) -> Unit,
    onBounds: (AppTab, androidx.compose.ui.geometry.Rect) -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    var dragging by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (dragging) 1.03f else 1f, label = "bar")
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .padding(bottom = 2.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .neonGlow(Color.Black.copy(alpha = 0.6f), 18.dp, CircleShape)
            .background(Theme.card.copy(alpha = 0.92f), CircleShape)
            .border(0.8.dp, Theme.colors.glassEdge, CircleShape)
            .padding(5.dp)
            // Slide a finger along the bar to scrub between tabs.
            .pointerInput(tabs) {
                detectHorizontalDragGestures(
                    onDragStart = { dragging = true },
                    onDragEnd = { dragging = false },
                    onDragCancel = { dragging = false },
                ) { change, _ ->
                    val index = (change.position.x / (size.width / tabs.size.toFloat())).toInt().coerceIn(0, tabs.lastIndex)
                    if (tabs[index].tab != selection) {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(tabs[index].tab)
                    }
                }
            },
    ) {
        val itemWidth = (maxWidth - 2.dp * (tabs.size - 1)) / tabs.size
        val index = tabs.indexOfFirst { it.tab == selection }.coerceAtLeast(0)
        val x by animateDpAsState((itemWidth + 2.dp) * index, spring(dampingRatio = 0.72f, stiffness = 450f), label = "pill")
        Box(
            Modifier.offset(x = x).width(itemWidth).height(50.dp)
                .graphicsLayer { scaleX = if (dragging) 1.14f else 1f; scaleY = if (dragging) 1.08f else 1f }
                .neonGlow(Theme.magenta, if (dragging) 20.dp else 12.dp, CircleShape)
                .background(Theme.neon, CircleShape)
                .border(0.8.dp, Color.White.copy(alpha = if (dragging) 0.5f else 0.25f), CircleShape),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            tabs.forEach { spec ->
                val selected = spec.tab == selection
                Box(
                    Modifier.width(itemWidth).height(50.dp).clip(CircleShape)
                        .onGloballyPositioned { coordinates ->
                            val p = coordinates.positionInRoot()
                            onBounds(spec.tab, androidx.compose.ui.geometry.Rect(p.x, p.y, p.x + coordinates.size.width, p.y + coordinates.size.height))
                        }
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onSelect(spec.tab)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        val color = if (selected) Color.White else Theme.secondary
                        Sym(if (selected) "${spec.symbol}.fill" else spec.symbol, size = 22.dp, tint = color)
                        T(spec.title, style = Type.system(10, FontWeight.SemiBold), color = color, maxLines = 1)
                    }
                    if (spec.badge > 0) {
                        Txt(
                            if (spec.badge > 99) "99+" else "${spec.badge}",
                            Modifier.align(Alignment.TopCenter).offset(x = 14.dp, y = 2.dp)
                                .background(Theme.accent, CircleShape).border(1.dp, Color.White.copy(alpha = 0.7f), CircleShape)
                                .padding(horizontal = 5.dp).widthIn(min = 7.dp),
                            style = Type.system(10, FontWeight.Bold), color = Color.White, align = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

// MARK: Sign out

/** Sign out with a confirmation, shown at the bottom of the profile and studio tabs. */
@Composable
fun SignOutButton() {
    val app = LocalAppState.current
    var confirm by remember { mutableStateOf(false) }
    GlassCard(Modifier.padding(top = 8.dp), padding = 14.dp, cornerRadius = 18.dp, onClick = { confirm = true }) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Sym("rectangle.portrait.and.arrow.right", tint = Theme.red)
            HSpace(8.dp)
            T("Sign out", style = Type.body.semibold, color = Theme.red)
        }
    }
    if (confirm) {
        ConfirmDialog("Sign out of EasySesh?", actions = listOf(DialogAction("Sign out", destructive = true) { app.scope.launch { app.signOut() } }), onDismiss = { confirm = false })
    }
}
