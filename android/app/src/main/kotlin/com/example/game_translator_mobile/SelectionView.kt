package com.example.game_translator_mobile

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View

class SelectionView(context: Context, private val onSelected: (Rect) -> Unit) : View(context) {

    private var startX = 0f
    private var startY = 0f
    private var endX = 0f
    private var endY = 0f
    private var isDragging = false

    private val rectPaint = Paint().apply {
        color = Color.argb(80, 108, 99, 255)
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint().apply {
        color = Color.argb(255, 108, 99, 255)
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }
    private val dimPaint = Paint().apply {
        color = Color.argb(120, 0, 0, 0)
        style = Paint.Style.FILL
    }
    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 40f
        textAlign = Paint.Align.CENTER
        setShadowLayer(4f, 0f, 2f, Color.BLACK)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (!isDragging) {
            // Instrução inicial
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dimPaint)
            canvas.drawText(
                "Arraste para selecionar a área",
                width / 2f, height / 2f, textPaint
            )
            canvas.drawText(
                "Toque em qualquer lugar para começar",
                width / 2f, height / 2f + 50f, textPaint.apply { textSize = 30f }
            )
            return
        }

        val left = minOf(startX, endX)
        val top = minOf(startY, endY)
        val right = maxOf(startX, endX)
        val bottom = maxOf(startY, endY)

        // Escurece fora da seleção
        canvas.drawRect(0f, 0f, width.toFloat(), top, dimPaint)
        canvas.drawRect(0f, bottom, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRect(0f, top, left, bottom, dimPaint)
        canvas.drawRect(right, top, width.toFloat(), bottom, dimPaint)

        // Área selecionada
        canvas.drawRect(left, top, right, bottom, rectPaint)
        canvas.drawRect(left, top, right, bottom, borderPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                startX = event.x
                startY = event.y
                endX = event.x
                endY = event.y
                isDragging = true
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                endX = event.x
                endY = event.y
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                endX = event.x
                endY = event.y
                val left = minOf(startX, endX).toInt()
                val top = minOf(startY, endY).toInt()
                val right = maxOf(startX, endX).toInt()
                val bottom = maxOf(startY, endY).toInt()

                if (right - left > 20 && bottom - top > 20) {
                    onSelected(Rect(left, top, right, bottom))
                }
                return true
            }
        }
        return false
    }
}
