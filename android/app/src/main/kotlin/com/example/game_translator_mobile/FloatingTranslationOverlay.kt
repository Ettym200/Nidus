package com.example.game_translator_mobile

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.provider.Settings

/**
 * Card flutuante reutilizável (tradução por tela / Live).
 */
object FloatingTranslationOverlay {
    private var resultView: View? = null
    private var windowManager: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var hideRunnable: Runnable? = null

    fun show(context: Context, text: String, style: String = "dark") {
        if (!Settings.canDrawOverlays(context)) return
        mainHandler.post {
            try {
                showInternal(context.applicationContext, text, style)
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    fun hide() {
        mainHandler.post {
            hideInternal()
        }
    }

    private fun hideInternal() {
        hideRunnable?.let { mainHandler.removeCallbacks(it) }
        hideRunnable = null
        val wm = windowManager
        val view = resultView
        if (wm != null && view != null) {
            try { wm.removeView(view) } catch (_: Exception) {}
        }
        resultView = null
    }

    private fun styleColors(style: String): Pair<Int, Int> {
        return when (style) {
            "transparent" -> Pair(Color.argb(120, 10, 10, 20), Color.argb(180, 255, 255, 255))
            "semi" -> Pair(Color.argb(180, 15, 20, 35), Color.argb(200, 108, 99, 255))
            "black" -> Pair(Color.argb(235, 0, 0, 0), Color.argb(200, 80, 80, 80))
            "blue" -> Pair(Color.argb(235, 8, 16, 40), Color.argb(200, 60, 140, 220))
            else -> Pair(Color.argb(235, 15, 15, 25), Color.argb(200, 108, 99, 255))
        }
    }

    private fun showInternal(context: Context, text: String, style: String) {
        hideInternal()

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
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
            y = (screenH * 0.62).toInt()
        }

        val colors = styleColors(style)
        val container = FrameLayout(context)
        container.background = android.graphics.drawable.GradientDrawable().apply {
            setColor(colors.first)
            setStroke(3, colors.second)
            cornerRadius = 16f
        }

        val lines = text.trim()
        val tv = TextView(context).apply {
            this.text = lines
            textSize = 16f
            setTextColor(Color.WHITE)
            setLineSpacing(4f, 1f)
            setPadding(22, 16, 52, 16)
            maxLines = 8
        }

        val closeBtn = TextView(context).apply {
            setText("✕")
            textSize = 14f
            setTextColor(Color.argb(200, 255, 255, 255))
            setPadding(10, 6, 10, 6)
            setBackgroundColor(
                Color.argb(
                    120,
                    Color.red(colors.second),
                    Color.green(colors.second),
                    Color.blue(colors.second)
                )
            )
        }
        val closeLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END
        ).apply { setMargins(0, 6, 6, 0) }

        container.addView(tv)
        container.addView(closeBtn, closeLp)

        var dragStartRawX = 0f
        var dragStartRawY = 0f
        var dragStartParamX = 0
        var dragStartParamY = 0
        var moved = false
        var currentWidth = boxWidth
        val minW = (screenW * 0.25).toInt()

        val scaleDetector = ScaleGestureDetector(
            context,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    currentWidth = (currentWidth * detector.scaleFactor)
                        .toInt().coerceIn(minW, screenW)
                    params.width = currentWidth
                    params.x = ((screenW - currentWidth) / 2).coerceIn(0, screenW - currentWidth)
                    wm.updateViewLayout(container, params)
                    return true
                }
            }
        )

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
                        if (kotlin.math.abs(dx) > 8 || kotlin.math.abs(dy) > 8) moved = true
                        if (moved) {
                            params.x = (dragStartParamX + dx).toInt()
                                .coerceIn(0, screenW - currentWidth)
                            params.y = (dragStartParamY + dy).toInt()
                                .coerceIn(0, screenH - 60)
                            wm.updateViewLayout(container, params)
                        }
                    }
                }
            }
            true
        }

        closeBtn.setOnClickListener { hideInternal() }

        resultView = container
        wm.addView(container, params)

        hideRunnable = Runnable { hideInternal() }
        mainHandler.postDelayed(hideRunnable!!, 45000)
    }
}
