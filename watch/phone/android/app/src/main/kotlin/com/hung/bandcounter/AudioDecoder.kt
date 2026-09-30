package com.hung.bandcounter

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Any audio file Android can play (MP3, M4A, WAV…) -> 16-bit PCM WAV.
 *
 * Dart cannot decode MP3, but PCM is just numbers it can multiply: this is
 * what lets the bundled clips be boosted past 100% (lib/services/clip_gain_service.dart).
 */
object AudioDecoder {
    private const val TIMEOUT_US = 10_000L

    /** Decodes [src] into a WAV at [dst]. Written to dst.part, then renamed. */
    fun decodeToWav(src: String, dst: String): Boolean {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(src)
            var track = -1
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) { track = i; break }
            }
            if (track < 0) return false
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var float = false

            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()

            val pcm = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            // A clip is seconds long; this only stops a codec that never ends.
            var guard = 0
            while (!outputDone && guard++ < 200_000) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (o >= 0) {
                    if (info.size > 0) {
                        val buf = codec.getOutputBuffer(o)!!
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        val bytes = ByteArray(info.size)
                        buf.get(bytes)
                        pcm.write(if (float) floatTo16(bytes) else bytes)
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                } else if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = codec.outputFormat
                    rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                }
            }
            if (!outputDone || pcm.size() == 0) return false
            val part = File("$dst.part")
            writeWav(part, pcm.toByteArray(), rate, channels)
            return part.renameTo(File(dst))
        } catch (e: Exception) {
            android.util.Log.w("AudioDecoder", "decode $src failed: ${e.message}")
            return false
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    private fun floatTo16(bytes: ByteArray): ByteArray {
        val src = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        val out = ByteBuffer.allocate(src.remaining() * 2).order(ByteOrder.LITTLE_ENDIAN)
        while (src.hasRemaining()) {
            val v = (src.get().coerceIn(-1f, 1f) * 32767f).toInt()
            out.putShort(v.toShort())
        }
        return out.array()
    }

    private fun writeWav(f: File, data: ByteArray, rate: Int, channels: Int) {
        val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray()); h.putInt(36 + data.size); h.put("WAVE".toByteArray())
        h.put("fmt ".toByteArray()); h.putInt(16); h.putShort(1); h.putShort(channels.toShort())
        h.putInt(rate); h.putInt(rate * channels * 2); h.putShort((channels * 2).toShort()); h.putShort(16)
        h.put("data".toByteArray()); h.putInt(data.size)
        RandomAccessFile(f, "rw").use { raf ->
            raf.setLength(0)
            raf.write(h.array())
            raf.write(data)
        }
    }
}
