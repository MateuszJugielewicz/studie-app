package com.easysesh.app.ui.features

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.easysesh.app.core.Dates
import com.easysesh.app.core.ImageCompressor
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.Story
import com.easysesh.app.model.StoryActivity
import com.easysesh.app.model.StoryAuthor
import com.easysesh.app.model.StudioStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Stories (like Instagram): a row of circles for everyone with a live story, a full-screen player
// (tap left/right, hold to pause), likes and replies, and posting a photo with a caption. Stories
// disappear after 24 hours. The poster sees who viewed, liked and replied, and can remove one.

private const val STORY_SECONDS = 6f

/** Shown at the top of Discover and the studio dashboard. */
@Composable
fun StoryBar() {
    val app = LocalAppState.current
    var authors by remember { mutableStateOf<List<StoryAuthor>?>(null) }
    var viewing by remember { mutableStateOf<Int?>(null) }
    var composing by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    val account = app.account
    val canPost = account != null && account.emailVerifiedAt != null && when (account.role) {
        UserRole.Artist -> !app.artistProfile?.artistName.isNullOrBlank()
        UserRole.StudioOwner -> app.ownedStudio?.status == StudioStatus.Approved
        else -> false
    }
    LaunchedEffect(account?.id, reload) {
        if (account != null) authors = runCatching { app.backend.storyFeed() }.getOrDefault(authors ?: emptyList())
    }
    val list = authors ?: return
    if (account == null || (!canPost && list.none { !it.isOwn })) return
    val own = list.firstOrNull { it.isOwn }
    val ordered = listOfNotNull(own) + list.filter { !it.isOwn }
    val myAvatar = if (app.role == UserRole.StudioOwner) app.ownedStudio?.photoUrls?.firstOrNull() else app.artistProfile?.avatarUrl

    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        if (canPost && own == null) {
            StoryCircle(tr("Your story"), myAvatar, StoryRing.Add, showsPlus = true, onPlus = { composing = true }) { composing = true }
        }
        ordered.forEachIndexed { index, author ->
            StoryCircle(if (author.isOwn) tr("Your story") else author.name, author.avatarUrl,
                if (author.allSeen) StoryRing.Seen else StoryRing.New, showsPlus = author.isOwn && canPost, onPlus = { composing = true }) {
                viewing = index
            }
        }
    }
    viewing?.let { start -> StoryViewer(ordered, start) { viewing = null; reload++ } }
    if (composing) StoryComposer(onClose = { composing = false }, onPosted = { reload++ })
}

private enum class StoryRing { New, Seen, Add }

@Composable
private fun StoryCircle(name: String, avatar: String?, ring: StoryRing, showsPlus: Boolean, onPlus: () -> Unit, onClick: () -> Unit) {
    Column(Modifier.width(72.dp).pressable(onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box {
            val border = when (ring) {
                StoryRing.New -> Modifier.border(3.dp, Theme.neon, CircleShape)
                else -> Modifier.border(1.5.dp, Theme.secondary.copy(alpha = 0.35f), CircleShape)
            }
            Box(border.padding(4.dp)) { Avatar(avatar, name, 58.dp) }
            if (showsPlus) {
                Box(Modifier.align(Alignment.BottomEnd).size(22.dp).background(Theme.neon, CircleShape).pressable(onClick = onPlus),
                    contentAlignment = Alignment.Center) { Sym("plus", size = 14.dp, tint = Color.White) }
            }
        }
        Txt(name, style = Type.caption2, maxLines = 1)
    }
}

/** Full-screen story player. */
@Composable
private fun StoryViewer(authors: List<StoryAuthor>, startIndex: Int, onClose: () -> Unit) {
    val app = LocalAppState.current
    var authorIndex by remember { mutableIntStateOf(startIndex) }
    var stories by remember { mutableStateOf<List<Story>?>(null) }
    var index by remember { mutableIntStateOf(0) }
    var progress by remember { mutableFloatStateOf(0f) }
    var holding by remember { mutableStateOf(false) }
    var reply by remember { mutableStateOf("") }
    var showActivity by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val author = authors[authorIndex]
    val story = stories?.getOrNull(index)
    val paused = holding || showActivity || confirmRemove || reporting || reply.isNotEmpty()

    fun next() {
        progress = 0f
        val list = stories
        when {
            list != null && index < list.size - 1 -> index++
            authorIndex < authors.size - 1 -> authorIndex++
            else -> onClose()
        }
    }
    fun previous() {
        progress = 0f
        if (index > 0) index-- else if (authorIndex > 0) authorIndex--
    }

    LaunchedEffect(authorIndex) {
        stories = null
        progress = 0f
        try {
            val list = app.backend.userStories(author.userId)
            if (list.isEmpty()) { next(); return@LaunchedEffect }
            stories = list
            index = if (author.isOwn) 0 else list.indexOfFirst { !it.seen }.coerceAtLeast(0)
        } catch (e: Exception) { error = e.userMessage }
    }
    LaunchedEffect(story?.id) {
        val s = story ?: return@LaunchedEffect
        if (!author.isOwn && !s.seen) runCatching { app.backend.markStoryViewed(s.id) }
    }
    LaunchedEffect(story?.id, paused) {
        while (story != null && !paused) {
            delay(50)
            progress += 0.05f / STORY_SECONDS
            if (progress >= 1f) { next(); break }
        }
    }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (story != null) {
                RemoteImage(story.mediaUrl, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            } else {
                ProgressSpinner(Modifier.align(Alignment.Center))
            }
            // Tap left for back, right for next; hold anywhere to pause.
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxHeight().pointerInput(story?.id) {
                    detectTapGestures(onPress = { holding = true; tryAwaitRelease(); holding = false }, onTap = { previous() })
                })
                Box(Modifier.weight(1.8f).fillMaxHeight().pointerInput(story?.id) {
                    detectTapGestures(onPress = { holding = true; tryAwaitRelease(); holding = false }, onTap = { next() })
                })
            }
            Column(
                Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent)))
                    .statusBarsPadding().padding(horizontal = 12.dp).padding(top = 10.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    (stories ?: emptyList()).forEachIndexed { i, _ ->
                        val fill = if (i < index) 1f else if (i == index) progress.coerceIn(0f, 1f) else 0f
                        Box(Modifier.weight(1f).height(2.5.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.35f))) {
                            Box(Modifier.fillMaxWidth(fill).fillMaxHeight().background(Color.White))
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Avatar(author.avatarUrl, author.name, 34.dp)
                    Txt(author.name, Modifier.weight(1f, fill = false), style = Type.subheadline.bold, color = Color.White, maxLines = 1)
                    if (author.isVerified) VerifiedBadge()
                    if (author.isPromoted) PromotedTag()
                    story?.let { Txt(Dates.relative(it.createdAt), style = Type.caption, color = Color.White.copy(alpha = 0.75f)) }
                    Fill()
                    if (story != null) {
                        if (author.isOwn) Sym("trash", Modifier.pressable { confirmRemove = true }, size = 20.dp, tint = Color.White)
                        else Sym("flag", Modifier.pressable { reporting = true }, size = 20.dp, tint = Color.White)
                    }
                    Sym("xmark", Modifier.pressable(onClick = onClose), size = 22.dp, tint = Color.White)
                }
            }
            if (story != null) {
                Column(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
                        .navigationBarsPadding().padding(horizontal = 12.dp).padding(top = 30.dp, bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    if (story.caption.isNotEmpty()) Txt(story.caption, style = Type.body.semibold, color = Color.White)
                    if (author.isOwn) {
                        Row(Modifier.background(Color.Black.copy(alpha = 0.35f), CircleShape).pressable { showActivity = true }.padding(horizontal = 14.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Sym("eye", size = 16.dp, tint = Color.White); Txt(L10n.format("%lld views", story.viewCount ?: 0), style = Type.subheadline.semibold, color = Color.White)
                            Sym("heart", size = 16.dp, tint = Color.White); Txt("${story.likeCount}", style = Type.subheadline.semibold, color = Color.White)
                            Sym("bubble.left", size = 16.dp, tint = Color.White); Txt("${story.replyCount ?: 0}", style = Type.subheadline.semibold, color = Color.White)
                        }
                    } else {
                        fun send() {
                            val text = reply.trim()
                            if (text.isEmpty()) return
                            app.scope.launch {
                                try { app.backend.replyToStory(story.id, text); reply = ""; info = "Reply sent." } catch (e: Exception) { error = e.userMessage }
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.weight(1f).height(44.dp).border(1.dp, Color.White.copy(alpha = 0.55f), CircleShape).padding(horizontal = 16.dp),
                                contentAlignment = Alignment.CenterStart) {
                                if (reply.isEmpty()) Txt(L10n.format("Reply to %@…", author.name), style = Type.subheadline, color = Color.White.copy(alpha = 0.75f), maxLines = 1)
                                BasicTextField(reply, { reply = it.take(1000) }, Modifier.fillMaxWidth(), singleLine = true,
                                    textStyle = Type.subheadline.copy(color = Color.White), cursorBrush = SolidColor(Color.White),
                                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }))
                            }
                            if (reply.isBlank()) {
                                Sym(if (story.likedByMe) "heart.fill" else "heart", Modifier.pressable {
                                    val like = !story.likedByMe
                                    stories = stories?.map { if (it.id == story.id) it.copy(likedByMe = like, likeCount = it.likeCount + if (like) 1 else -1) else it }
                                    app.scope.launch { runCatching { app.backend.likeStory(story.id, like) }.onFailure { error = it.userMessage } }
                                }, size = 28.dp, tint = if (story.likedByMe) Color(0xFFFF3D6E) else Color.White)
                            } else {
                                Sym("paperplane.fill", Modifier.pressable { send() }, size = 24.dp, tint = Color.White)
                            }
                        }
                    }
                }
            }
        }
        if (showActivity && story != null) Sheet({ showActivity = false }) { StoryActivityView(story.id) }
        if (reporting) Sheet({ reporting = false }) {
            ReportSheet(if (author.studioId == null) ReportTarget.User else ReportTarget.Studio, author.studioId ?: author.userId)
        }
        if (confirmRemove && story != null) {
            ConfirmDialog("Remove this story?", tr("It disappears for everyone right away."), listOf(DialogAction("Remove", destructive = true) {
                app.scope.launch {
                    try {
                        app.backend.removeStory(story.id)
                        val rest = stories.orEmpty().filter { it.id != story.id }
                        if (rest.isEmpty()) onClose() else { stories = rest; index = index.coerceAtMost(rest.size - 1); progress = 0f }
                    } catch (e: Exception) { error = e.userMessage }
                }
            }), { confirmRemove = false })
        }
        info?.let { message -> ConfirmDialog(message, null, listOf(DialogAction("OK") { info = null }), { info = null }) }
        ErrorAlert(error) { error = null }
    }
}

/** For the poster: who viewed, liked and replied to a story. */
@Composable
private fun StoryActivityView(storyId: String) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var people by remember { mutableStateOf<List<StoryActivity>?>(null) }
    LaunchedEffect(storyId) { people = runCatching { app.backend.storyActivity(storyId) }.getOrDefault(emptyList()) }
    NavScreen("Activity", actions = { ToolbarButton("Done", bold = true) { dismiss() } }) {
        val list = people
        when {
            list == null -> ProgressSpinner()
            list.isEmpty() -> T("No one has seen this story yet.", style = Type.subheadline, color = Theme.secondary)
            else -> list.forEach { person ->
                GlassCard(padding = 12.dp) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                        Avatar(person.avatarUrl, person.name, 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(person.name, style = Type.subheadline.semibold)
                                if (person.liked) Sym("heart.fill", size = 14.dp, tint = Color(0xFFFF3D6E))
                            }
                            val reply = person.reply
                            val viewed = person.viewedAt
                            if (reply != null) Txt(reply, style = Type.footnote)
                            else if (viewed != null) Txt(Dates.relative(viewed), style = Type.caption, color = Theme.secondary)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Making a story, like Instagram: the camera opens straight away (back camera, flip for a selfie),
 * with a button for the camera roll. After taking or choosing a photo: add a caption and share.
 * Without camera permission it falls back to the camera roll.
 */
@Composable
private fun StoryComposer(onClose: () -> Unit, onPosted: () -> Unit) {
    val app = LocalAppState.current
    val context = LocalContext.current
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    var hasCamera by remember {
        mutableStateOf(androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED)
    }
    var cameraDenied by remember { mutableStateOf(false) }
    var front by remember { mutableStateOf(false) }
    var photo by remember { mutableStateOf<ByteArray?>(null) }
    var caption by remember { mutableStateOf("") }
    var isPosting by remember { mutableStateOf(false) }
    var isCapturing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val imageCapture = remember { androidx.camera.core.ImageCapture.Builder().setCaptureMode(androidx.camera.core.ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCamera = granted
        cameraDenied = !granted
    }
    LaunchedEffect(Unit) { if (!hasCamera) permission.launch(android.Manifest.permission.CAMERA) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        app.scope.launch { photo = withContext(Dispatchers.IO) { ImageCompressor.jpeg(context, uri, 1440, 85) } }
    }
    val preview = remember(photo) { photo?.let { bytes -> android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() } }

    fun capture() {
        if (isCapturing) return
        isCapturing = true
        val file = java.io.File.createTempFile("story", ".jpg", context.cacheDir)
        val options = androidx.camera.core.ImageCapture.OutputFileOptions.Builder(file)
            .setMetadata(androidx.camera.core.ImageCapture.Metadata().apply { isReversedHorizontal = front })
            .build()
        imageCapture.takePicture(options, androidx.core.content.ContextCompat.getMainExecutor(context), object : androidx.camera.core.ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: androidx.camera.core.ImageCapture.OutputFileResults) {
                app.scope.launch {
                    photo = withContext(Dispatchers.IO) { ImageCompressor.jpeg(context, android.net.Uri.fromFile(file), 1440, 85).also { file.delete() } }
                    isCapturing = false
                }
            }
            override fun onError(exception: androidx.camera.core.ImageCaptureException) {
                isCapturing = false
                error = exception.message ?: tr("Couldn't take the photo.")
            }
        })
    }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            when {
                preview != null -> androidx.compose.foundation.Image(preview, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                hasCamera -> {
                    // Live camera preview (CameraX), rebound when switching front/back.
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { ctx -> androidx.camera.view.PreviewView(ctx).apply { scaleType = androidx.camera.view.PreviewView.ScaleType.FILL_CENTER } },
                        modifier = Modifier.fillMaxSize(),
                        update = { view ->
                            val providerFuture = androidx.camera.lifecycle.ProcessCameraProvider.getInstance(view.context)
                            providerFuture.addListener({
                                val provider = providerFuture.get()
                                val previewUseCase = androidx.camera.core.Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
                                val selector = if (front) androidx.camera.core.CameraSelector.DEFAULT_FRONT_CAMERA else androidx.camera.core.CameraSelector.DEFAULT_BACK_CAMERA
                                runCatching {
                                    provider.unbindAll()
                                    provider.bindToLifecycle(lifecycleOwner, selector, previewUseCase, imageCapture)
                                }.onFailure { error = tr("The camera isn't available.") }
                            }, androidx.core.content.ContextCompat.getMainExecutor(view.context))
                        },
                    )
                    androidx.compose.runtime.DisposableEffect(Unit) {
                        onDispose { runCatching { androidx.camera.lifecycle.ProcessCameraProvider.getInstance(context).get().unbindAll() } }
                    }
                }
                else -> Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Sym("photo.badge.plus", size = 40.dp, tint = Color.White)
                    Txt(tr(if (cameraDenied) "The camera isn't available. Allow camera access in your settings, or choose a photo from your camera roll." else "Starting the camera…"),
                        style = Type.subheadline, color = Color.White)
                    PrimaryButton("Choose a photo") { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                }
            }
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Sym("xmark", Modifier.pressable { if (photo != null) photo = null else onClose() }, size = 24.dp, tint = Color.White)
                Fill()
                T("New story", style = Type.subheadline.bold, color = Color.White)
                Fill()
                Box(Modifier.size(24.dp))
            }
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
                    .navigationBarsPadding().padding(horizontal = 16.dp).padding(top = 30.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (photo != null) {
                    Box(Modifier.fillMaxWidth().height(44.dp).border(1.dp, Color.White.copy(alpha = 0.55f), CircleShape).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                        if (caption.isEmpty()) Txt(tr("Add a caption (optional)"), style = Type.subheadline, color = Color.White.copy(alpha = 0.75f))
                        BasicTextField(caption, { caption = it.take(200) }, Modifier.fillMaxWidth(), singleLine = true,
                            textStyle = Type.subheadline.copy(color = Color.White), cursorBrush = SolidColor(Color.White))
                    }
                    Txt(tr("Stories are shown to people on EasySesh for 24 hours. Keep it about your music or studio – the community guidelines apply."),
                        style = Type.caption, color = Color.White.copy(alpha = 0.8f))
                    PrimaryButton(if (isPosting) "Posting…" else "Share story", Modifier.fillMaxWidth(), enabled = !isPosting) {
                        val data = photo ?: return@PrimaryButton
                        isPosting = true
                        app.scope.launch {
                            try {
                                app.backend.postStory(data, caption.trim())
                                onPosted()
                                onClose()
                            } catch (e: Exception) { error = e.userMessage } finally { isPosting = false }
                        }
                    }
                } else {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(46.dp).border(2.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
                            .background(Color.Black.copy(alpha = 0.25f))
                            .pressable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            contentAlignment = Alignment.Center) { Sym("photo.on.rectangle", size = 22.dp, tint = Color.White) }
                        Box(Modifier.size(76.dp).border(4.dp, Color.White, CircleShape).padding(8.dp).clip(CircleShape)
                            .background(if (hasCamera && !isCapturing) Color.White else Color.White.copy(alpha = 0.4f))
                            .pressable(enabled = hasCamera && !isCapturing) { capture() })
                        Box(Modifier.size(46.dp).border(2.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
                            .background(Color.Black.copy(alpha = 0.25f)).pressable(enabled = hasCamera) { front = !front },
                            contentAlignment = Alignment.Center) { Sym("arrow.triangle.2.circlepath.camera", size = 22.dp, tint = Color.White) }
                    }
                }
            }
        }
        ErrorAlert(error) { error = null }
    }
}
