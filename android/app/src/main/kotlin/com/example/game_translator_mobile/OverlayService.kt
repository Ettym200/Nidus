package com.example.game_translator_mobile

import android.app.*
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.provider.MediaStore
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.DisplayMetrics
import android.view.*
import android.view.ScaleGestureDetector
import android.widget.*
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.Base64

class OverlayService : Service() {
    private val CHANNEL_ID = "overlay_channel"
    private val NOTIF_ID = 1

    private var windowManager: WindowManager? = null
    private var overlayRoot: View? = null

    // Floating button
    private var fabView: View? = null
    private var fabParams: WindowManager.LayoutParams? = null

    // Selection overlay
    private var selectionView: SelectionView? = null

    // Translation result overlay
    private var resultView: View? = null
    private var resultParams: WindowManager.LayoutParams? = null

    // Capture
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenWidth = 0
    private var screenHeight = 0
    private var screenDensity = 0

    // API config
    private var apiKey = ""
    private var provider = ""
    private var model = ""
    private var language = ""
    private var customUrl = ""
    private var overlayStyle = "dark"

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val client = OkHttpClient()

    private var orientationReceiver: BroadcastReceiver? = null
    private var captureThread: HandlerThread? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager!!.defaultDisplay.getMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        screenDensity = metrics.densityDpi
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Nidus")
            .setContentText("Overlay ativo — toque no botão flutuante")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()
        startForeground(NOTIF_ID, notification)

        apiKey = intent?.getStringExtra("apiKey") ?: ""
        provider = intent?.getStringExtra("provider") ?: "openai"
        model = intent?.getStringExtra("model") ?: ""
        language = intent?.getStringExtra("language") ?: "Português"
        customUrl = intent?.getStringExtra("customUrl") ?: ""
        overlayStyle = intent?.getStringExtra("overlayStyle") ?: "dark"

        val resultCode = intent?.getIntExtra("resultCode", 0) ?: 0
        val projData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            intent?.getParcelableExtra("projectionData", Intent::class.java)
        else
            @Suppress("DEPRECATION") intent?.getParcelableExtra("projectionData")

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        if (projData != null && resultCode != 0) {
            mediaProjection = mgr.getMediaProjection(resultCode, projData)
            setupCapture()
        }

        registerOrientationReceiver()
        showFab()
        return START_NOT_STICKY
    }

    private fun registerOrientationReceiver() {
        orientationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                windowManager?.defaultDisplay?.getRealMetrics(metrics)
                val newW = metrics.widthPixels
                val newH = metrics.heightPixels
                if (newW != screenWidth || newH != screenHeight) {
                    screenWidth = newW
                    screenHeight = newH
                    swapImageReader()
                }
            }
        }
        registerReceiver(orientationReceiver, IntentFilter(Intent.ACTION_CONFIGURATION_CHANGED))
    }

    private fun swapImageReader() {
        val oldReader = imageReader
        val newReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        setupImageListener(newReader)
        // Redimensiona o VirtualDisplay para a nova orientação E troca o surface
        virtualDisplay?.resize(screenWidth, screenHeight, screenDensity)
        virtualDisplay?.setSurface(newReader.surface)
        imageReader = newReader
        Handler(Looper.getMainLooper()).postDelayed({ oldReader?.close() }, 500)
    }

    private fun showFab() {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        fabParams = WindowManager.LayoutParams(
            160, WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 300
        }

        // Container vertical: botão principal em cima, botão de re-traduzir embaixo
        val fab = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        // ----- Botão principal: selecionar área + traduzir -----
        val mainBtn = FrameLayout(this)
        val iconView = try {
            val stream = assets.open("flutter_assets/assets/icon.png")
            val bitmap = android.graphics.BitmapFactory.decodeStream(stream)
            stream.close()
            ImageView(this).apply {
                setImageBitmap(bitmap)
                scaleType = ImageView.ScaleType.FIT_CENTER
                setPadding(12, 12, 12, 12)
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(Color.argb(210, 20, 20, 40))
                    cornerRadius = 28f
                }
            }
        } catch (e: Exception) {
            TextView(this).apply {
                setText("🌐")
                textSize = 32f
                gravity = Gravity.CENTER
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(Color.argb(200, 108, 99, 255))
                    cornerRadius = 28f
                }
                setPadding(16, 16, 16, 16)
            }
        }
        mainBtn.addView(iconView, FrameLayout.LayoutParams(160, 160))

        // Botão ✕ no canto superior direito para fechar o overlay
        val closeBtn = TextView(this).apply {
            setText("✕")
            textSize = 12f
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextColor(Color.WHITE)
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.argb(235, 200, 40, 40))
            }
        }
        val closeBtnLp = FrameLayout.LayoutParams(44, 44).apply {
            gravity = Gravity.TOP or Gravity.END
        }
        mainBtn.addView(closeBtn, closeBtnLp)
        closeBtn.setOnClickListener { stopSelf() }

        // Drag + click no botão principal (move o bloco flutuante inteiro)
        var startX = 0f; var startY = 0f
        var moved = false
        mainBtn.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX - fabParams!!.x
                    startY = event.rawY - fabParams!!.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val nx = (event.rawX - startX).toInt()
                    val ny = (event.rawY - startY).toInt()
                    if (Math.abs(nx - fabParams!!.x) > 5 || Math.abs(ny - fabParams!!.y) > 5) {
                        moved = true
                    }
                    fabParams!!.x = nx
                    fabParams!!.y = ny
                    windowManager?.updateViewLayout(fab, fabParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) showSelectionOverlay()
                    true
                }
                else -> false
            }
        }

        // ----- Botão de re-traduzir: usa a última área já selecionada -----
        val retranslateBtn = TextView(this).apply {
            setText("⟳")
            textSize = 34f
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextColor(Color.WHITE)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.argb(235, 40, 150, 100))
                cornerRadius = 28f
            }
            setOnClickListener { retranslateLast() }
        }
        val retranslateLp = LinearLayout.LayoutParams(160, 120).apply {
            topMargin = 14
        }

        fab.addView(mainBtn, LinearLayout.LayoutParams(160, 160))
        fab.addView(retranslateBtn, retranslateLp)

        fabView = fab
        windowManager?.addView(fab, fabParams)
    }

    private var lastBitmap: Bitmap? = null
    private var preCaptureBitmap: Bitmap? = null  // Frame capturado ANTES do overlay aparecer
    private var lastRect: Rect? = null            // Última área selecionada, para re-traduzir

    private fun showSelectionOverlay() {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager?.defaultDisplay?.getRealMetrics(metrics)
        val currentW = metrics.widthPixels
        val currentH = metrics.heightPixels

        val bmp = latestBitmap

        // Se o bitmap já tem as dimensões certas da orientação atual, usa imediatamente
        if (bmp != null && bmp.width == currentW && bmp.height == currentH) {
            preCaptureBitmap = bmp
            _showSelectionOverlay()
            return
        }

        // Bitmap é nulo ou tem dimensões erradas (virou a tela) — recria o reader e aguarda
        if (currentW != screenWidth || currentH != screenHeight) {
            screenWidth = currentW
            screenHeight = currentH
            screenDensity = metrics.densityDpi
        }
        swapImageReader()

        // Tenta até 10 vezes com intervalo de 100ms esperando um frame com dimensões corretas
        var tries = 0
        val check = object : Runnable {
            override fun run() {
                val fresh = latestBitmap
                if ((fresh != null && fresh.width == currentW && fresh.height == currentH) || tries >= 10) {
                    preCaptureBitmap = fresh
                    _showSelectionOverlay()
                } else {
                    tries++
                    Handler(Looper.getMainLooper()).postDelayed(this, 100)
                }
            }
        }
        Handler(Looper.getMainLooper()).postDelayed(check, 100)
    }

    private fun grabFrame(): Bitmap? {
        // Drena frames velhos para pegar o mais recente
        var image = imageReader?.acquireLatestImage()
        var tries = 0
        while (image == null && tries < 25) {
            Thread.sleep(100)
            image = imageReader?.acquireLatestImage()
            tries++
        }
        if (image == null) return null

        return try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride

            // largura real com padding
            val bmpWidth = rowStride / pixelStride

            val bmp = Bitmap.createBitmap(bmpWidth, screenHeight, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(buffer)
            image.close()

            // Corta para a largura real da tela se necessário
            if (bmpWidth != screenWidth) {
                Bitmap.createBitmap(bmp, 0, 0, screenWidth, screenHeight)
            } else {
                bmp
            }
        } catch (e: Exception) {
            image.close()
            null
        }
    }

    private fun _showSelectionOverlay() {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        val sel = SelectionView(this) { rect ->
            windowManager?.removeView(selectionView)
            selectionView = null
            captureAndTranslate(rect)
        }
        selectionView = sel
        windowManager?.addView(sel, params)
    }

    private var latestBitmap: Bitmap? = null

    private fun setupImageListener(reader: ImageReader) {
        captureThread?.quitSafely()
        val thread = HandlerThread("capture_thread_${System.currentTimeMillis()}").also { it.start() }
        captureThread = thread
        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val plane = image.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val imgWidth = image.width
                val imgHeight = image.height
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                image.close()
                val bmpWidth = rowStride / pixelStride
                val bmp = Bitmap.createBitmap(bmpWidth, imgHeight, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(bytes))
                latestBitmap = if (bmpWidth != imgWidth) Bitmap.createBitmap(bmp, 0, 0, imgWidth, imgHeight) else bmp
            } catch (e: Exception) {
                try { image.close() } catch (_: Exception) {}
            }
        }, Handler(thread.looper))
    }

    private fun setupCapture() {
        val reader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        setupImageListener(reader)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {}
            }, Handler(Looper.getMainLooper()))
        }

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "cap", screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, null
        )
    }

    private fun captureAndTranslate(rect: Rect) {
        // Guarda a área para permitir re-traduzir depois sem selecionar de novo
        lastRect = Rect(rect)
        // Usa o frame capturado ANTES do overlay escuro aparecer
        translateRect(rect, preCaptureBitmap)
    }

    // Re-traduz a última área selecionada, pegando um frame novo da tela.
    private fun retranslateLast() {
        val rect = lastRect
        if (rect == null) {
            showResult("Nenhuma área selecionada ainda.\nToque no botão principal para marcar a área.")
            return
        }
        // Sem overlay de seleção aqui, então usamos o frame mais recente da captura contínua
        translateRect(Rect(rect), latestBitmap)
    }

    private fun translateRect(rect: Rect, frame: Bitmap?) {
        showResult("Capturando...")
        val fullFrame = frame
        scope.launch(Dispatchers.IO) {
            try {
                val full = fullFrame
                if (full == null) {
                    withContext(Dispatchers.Main) { showResult("Sem frame — tente novamente") }
                    return@launch
                }

                if (full.width < 10 || full.height < 10) {
                    withContext(Dispatchers.Main) { showResult("Bitmap inválido: ${full.width}x${full.height}") }
                    return@launch
                }

                // Escala coordenadas do display atual para o espaço do bitmap
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
                val scaleX = full.width.toFloat() / metrics.widthPixels
                val scaleY = full.height.toFloat() / metrics.heightPixels

                val left = (rect.left * scaleX).toInt().coerceIn(0, full.width - 1)
                val top = (rect.top * scaleY).toInt().coerceIn(0, full.height - 1)
                val right = (rect.right * scaleX).toInt().coerceIn(left + 50, full.width)
                val bottom = (rect.bottom * scaleY).toInt().coerceIn(top + 50, full.height)

                val cropped = Bitmap.createBitmap(full, left, top, right - left, bottom - top)

                val stream = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                val bytes = stream.toByteArray()

                if (bytes.size < 100) {
                    withContext(Dispatchers.Main) { showResult("JPEG vazio: ${bytes.size} bytes, crop: ${right-left}x${bottom-top}, rect: $rect, full: ${full.width}x${full.height}") }
                    return@launch
                }

                val b64 = Base64.getEncoder().encodeToString(bytes)
                val translation = callApi(b64)
                withContext(Dispatchers.Main) {
                    showResult(translation.ifEmpty { "Nenhum texto encontrado." })
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { showResult("Erro: ${e.message}") }
            }
        }
    }

    private fun callApi(b64: String): String {
        val prompt = "Esta é uma captura de tela de um jogo. " +
                "Extraia APENAS o texto de legenda ou diálogo visível (ignore HUD, números, nomes de missão, ícones). " +
                "Traduza esse texto para $language. " +
                "Responda SOMENTE com a tradução, sem explicações. " +
                "Se não houver legenda ou diálogo, responda com uma string vazia."

        return if (provider == "anthropic") {
            callAnthropic(b64, prompt)
        } else {
            callOpenAICompat(b64, prompt)
        }
    }

    private fun callOpenAICompat(b64: String, prompt: String): String {
        val baseUrl = when (provider) {
            "openrouter" -> "https://openrouter.ai/api/v1"
            "groq" -> "https://api.groq.com/openai/v1"
            "custom" -> customUrl
            else -> "https://api.openai.com/v1"
        }
        val mdl = model.ifEmpty {
            when (provider) {
                "openrouter" -> "openai/gpt-4o-mini"
                "groq" -> "meta-llama/llama-4-scout-17b-16e-instruct"
                else -> "gpt-4o-mini"
            }
        }

        val body = JSONObject().apply {
            put("model", mdl)
            put("max_tokens", 300)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", JSONArray().apply {
                    put(JSONObject().apply { put("type", "text"); put("text", prompt) })
                    put(JSONObject().apply {
                        put("type", "image_url")
                        put("image_url", JSONObject().put("url", "data:image/jpeg;base64,$b64"))
                    })
                })
            }))
        }

        val req = Request.Builder()
            .url("$baseUrl/chat/completions")
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()

        val resp = client.newCall(req).execute()
        val rawBody = resp.body?.string() ?: "{}"
        if (!resp.isSuccessful) throw Exception("HTTP ${resp.code}: $rawBody")
        val json = JSONObject(rawBody)
        if (!json.has("choices")) throw Exception(rawBody)
        return json.getJSONArray("choices").getJSONObject(0)
            .getJSONObject("message").getString("content").trim()
    }

    private fun callAnthropic(b64: String, prompt: String): String {
        val mdl = model.ifEmpty { "claude-haiku-4-5-20251001" }
        val body = JSONObject().apply {
            put("model", mdl)
            put("max_tokens", 300)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", JSONArray().apply {
                    put(JSONObject().apply {
                        put("type", "image")
                        put("source", JSONObject().apply {
                            put("type", "base64")
                            put("media_type", "image/jpeg")
                            put("data", b64)
                        })
                    })
                    put(JSONObject().apply { put("type", "text"); put("text", prompt) })
                })
            }))
        }

        val req = Request.Builder()
            .url("https://api.anthropic.com/v1/messages")
            .addHeader("x-api-key", apiKey)
            .addHeader("anthropic-version", "2023-06-01")
            .addHeader("Content-Type", "application/json")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()

        val resp = client.newCall(req).execute()
        val json = JSONObject(resp.body?.string() ?: "{}")
        return json.getJSONArray("content").getJSONObject(0).getString("text").trim()
    }

    private fun overlayStyleColors(style: String): Pair<Int, Int> {
        // background ARGB, border ARGB
        return when (style) {
            "transparent" -> Pair(Color.argb(120, 10, 10, 20), Color.argb(180, 255, 255, 255))
            "semi" -> Pair(Color.argb(180, 15, 20, 35), Color.argb(200, 108, 99, 255))
            "black" -> Pair(Color.argb(235, 0, 0, 0), Color.argb(200, 80, 80, 80))
            "blue" -> Pair(Color.argb(235, 8, 16, 40), Color.argb(200, 60, 140, 220))
            else -> Pair(Color.argb(235, 15, 15, 25), Color.argb(200, 108, 99, 255)) // dark
        }
    }

    private fun showResult(text: String) {
        resultView?.let { try { windowManager?.removeView(it) } catch (e: Exception) {} }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager?.defaultDisplay?.getRealMetrics(metrics)
        val screenW = metrics.widthPixels
        val screenH = metrics.heightPixels
        val boxWidth = (screenW * 0.82).toInt()

        val params = WindowManager.LayoutParams(
            boxWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (screenW - boxWidth) / 2
            y = (screenH * 0.68).toInt()
        }

        // Caixa de texto com X no canto
        val styleColors = overlayStyleColors(overlayStyle)
        val container = FrameLayout(this).apply {
            setPadding(0, 0, 0, 0)
        }
        container.background = android.graphics.drawable.GradientDrawable().apply {
            setColor(styleColors.first)
            setStroke(3, styleColors.second)
            cornerRadius = 16f
        }

        val tv = TextView(this).apply {
            this.text = text
            textSize = 16f
            setTextColor(Color.WHITE)
            setLineSpacing(4f, 1f)
            setPadding(22, 16, 52, 16)
        }

        val closeBtn = TextView(this).apply {
            setText("✕")
            textSize = 14f
            setTextColor(Color.argb(200, 255, 255, 255))
            setPadding(10, 6, 10, 6)
            setBackgroundColor(Color.argb(120, Color.red(styleColors.second), Color.green(styleColors.second), Color.blue(styleColors.second)))
        }
        val closeLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END
        ).apply { setMargins(0, 6, 6, 0) }

        container.addView(tv)
        container.addView(closeBtn, closeLp)

        // Arrastar (1 dedo) + pinça para redimensionar largura (2 dedos)
        var dragStartRawX = 0f
        var dragStartRawY = 0f
        var dragStartParamX = 0
        var dragStartParamY = 0
        var moved = false
        var currentWidth = boxWidth
        val minW = (screenW * 0.25).toInt()

        val scaleDetector = ScaleGestureDetector(this,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    currentWidth = (currentWidth * detector.scaleFactor)
                        .toInt().coerceIn(minW, screenW)
                    params.width = currentWidth
                    params.x = ((screenW - currentWidth) / 2).coerceIn(0, screenW - currentWidth)
                    windowManager?.updateViewLayout(container, params)
                    return true
                }
            })

        container.setOnTouchListener { _, event ->
            scaleDetector.onTouchEvent(event)
            if (!scaleDetector.isInProgress) {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartRawX = event.rawX
                        dragStartRawY = event.rawY
                        dragStartParamX = params.x
                        dragStartParamY = params.y
                        moved = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - dragStartRawX
                        val dy = event.rawY - dragStartRawY
                        if (Math.abs(dx) > 8 || Math.abs(dy) > 8) moved = true
                        if (moved) {
                            params.x = (dragStartParamX + dx).toInt().coerceIn(0, screenW - currentWidth)
                            params.y = (dragStartParamY + dy).toInt().coerceIn(0, screenH - 60)
                            windowManager?.updateViewLayout(container, params)
                        }
                    }
                }
            }
            true
        }

        closeBtn.setOnClickListener {
            try { windowManager?.removeView(container) } catch (e: Exception) {}
            resultView = null
        }

        resultView = container
        windowManager?.addView(container, params)

        Handler(Looper.getMainLooper()).postDelayed({
            try { windowManager?.removeView(container) } catch (e: Exception) {}
            if (resultView == container) resultView = null
        }, 60000)
    }

    private fun saveDebugImage(bmp: Bitmap, name: String) {
        try {
            val cv = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "$name.jpg")
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/GameTranslator")
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv)
            uri?.let {
                contentResolver.openOutputStream(it)?.use { out ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }
            }
        } catch (e: Exception) { /* ignora erros de debug */ }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Game Translator Overlay",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        orientationReceiver?.let { try { unregisterReceiver(it) } catch (e: Exception) {} }
        captureThread?.quitSafely()
        fabView?.let { try { windowManager?.removeView(it) } catch (e: Exception) {} }
        selectionView?.let { try { windowManager?.removeView(it) } catch (e: Exception) {} }
        resultView?.let { try { windowManager?.removeView(it) } catch (e: Exception) {} }
        mediaProjection?.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
