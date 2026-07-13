package com.example.game_translator_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.sqrt

/**
 * Captura áudio INTERNO (playback) via MediaProjection — não usa o microfone,
 * então não pausa lives/vídeos com audio focus.
 * Requer Android 10+ (API 29).
 */
class LiveAudioService : Service() {
    companion object {
        const val CHANNEL_ID = "nidus_live_audio"
        const val NOTIF_ID = 42
        const val ACTION_STOP = "com.nidus.app.STOP_LIVE_AUDIO"

        @Volatile
        var chunkListener: ((String) -> Unit)? = null

        @Volatile
        var statusListener: ((String) -> Unit)? = null

        const val SAMPLE_RATE = 16000
        const val CHUNK_MS = 5500
    }

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    @Volatile private var running = false
    private var captureThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCapture()
            stopSelf()
            return START_NOT_STICKY
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            statusListener?.invoke("Áudio interno precisa de Android 10+")
            stopSelf()
            return START_NOT_STICKY
        }

        val resultCode = intent?.getIntExtra("resultCode", 0) ?: 0
        val projData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            intent?.getParcelableExtra("projectionData", Intent::class.java)
        else
            @Suppress("DEPRECATION") intent?.getParcelableExtra("projectionData")

        if (projData == null || resultCode == 0) {
            statusListener?.invoke("Permissão de captura negada")
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIF_ID, buildNotification())

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mgr.getMediaProjection(resultCode, projData)

        startCapture()
        return START_STICKY
    }

    private fun startCapture() {
        if (running) return
        val projection = mediaProjection ?: return

        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()

        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = (minBuf * 2).coerceAtLeast(SAMPLE_RATE * 2)

        try {
            audioRecord = AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setAudioPlaybackCaptureConfig(config)
                .build()
        } catch (e: Exception) {
            statusListener?.invoke("Erro ao iniciar captura: ${e.message}")
            stopSelf()
            return
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            statusListener?.invoke("AudioRecord não inicializou")
            stopSelf()
            return
        }

        running = true
        statusListener?.invoke("Capturando áudio interno...")
        audioRecord?.startRecording()

        val samplesPerChunk = SAMPLE_RATE * CHUNK_MS / 1000
        val readBuf = ShortArray(2048)

        captureThread = thread(name = "nidus-live-audio", isDaemon = true) {
            val pcm = ByteArrayOutputStream()
            var collected = 0
            while (running) {
                val n = audioRecord?.read(readBuf, 0, readBuf.size) ?: -1
                if (n <= 0) {
                    Thread.sleep(20)
                    continue
                }
                val bytes = ByteArray(n * 2)
                ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(readBuf, 0, n)
                pcm.write(bytes)
                collected += n

                if (collected >= samplesPerChunk) {
                    val pcmBytes = pcm.toByteArray()
                    pcm.reset()
                    collected = 0
                    if (rms(pcmBytes) < 180) {
                        // Silêncio — não manda pra API
                        continue
                    }
                    try {
                        val wav = pcmToWav(pcmBytes, SAMPLE_RATE)
                        val file = File(cacheDir, "live_chunk_${System.currentTimeMillis()}.wav")
                        FileOutputStream(file).use { it.write(wav) }
                        chunkListener?.invoke(file.absolutePath)
                    } catch (e: Exception) {
                        statusListener?.invoke("Erro no chunk: ${e.message}")
                    }
                }
            }
        }
    }

    private fun rms(pcm: ByteArray): Double {
        if (pcm.size < 4) return 0.0
        var sum = 0.0
        var count = 0
        var i = 0
        while (i + 1 < pcm.size) {
            val s = ((pcm[i + 1].toInt() shl 8) or (pcm[i].toInt() and 0xFF)).toShort().toInt()
            sum += (s * s).toDouble()
            count++
            i += 2
        }
        if (count == 0) return 0.0
        return sqrt(sum / count)
    }

    private fun pcmToWav(pcm: ByteArray, sampleRate: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val channels = 1
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val dataSize = pcm.size
        val total = 36 + dataSize
        fun writeInt(v: Int) {
            out.write(v and 0xff)
            out.write(v shr 8 and 0xff)
            out.write(v shr 16 and 0xff)
            out.write(v shr 24 and 0xff)
        }
        fun writeShort(v: Int) {
            out.write(v and 0xff)
            out.write(v shr 8 and 0xff)
        }
        out.write("RIFF".toByteArray())
        writeInt(total)
        out.write("WAVE".toByteArray())
        out.write("fmt ".toByteArray())
        writeInt(16)
        writeShort(1)
        writeShort(channels)
        writeInt(sampleRate)
        writeInt(byteRate)
        writeShort(channels * bitsPerSample / 8)
        writeShort(bitsPerSample)
        out.write("data".toByteArray())
        writeInt(dataSize)
        out.write(pcm)
        return out.toByteArray()
    }

    private fun stopCapture() {
        running = false
        try { captureThread?.join(1500) } catch (_: Exception) {}
        captureThread = null
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        statusListener?.invoke("Parado")
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "Nidus Live", NotificationManager.IMPORTANCE_LOW
            )
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Nidus Live")
            .setContentText("Capturando áudio interno da tela")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }
}
