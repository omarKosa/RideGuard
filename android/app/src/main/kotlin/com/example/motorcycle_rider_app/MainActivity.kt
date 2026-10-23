package com.example.motorcycle_rider_app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Crash alarm, vibration and emergency calls for `rideguard/emergency`. */
class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var savedAlarmVolume: Int? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAlarm" -> {
                        startAlarm(call.argument<Boolean>("urgent") ?: true)
                        result.success(null)
                    }
                    "stopAlarm" -> {
                        stopAlarm()
                        result.success(null)
                    }
                    "call" -> result.success(placeCall(call.argument<String>("number")))
                    "requestCallPermission" -> requestCallPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startAlarm(urgent: Boolean) {
        stopAlarm()
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (urgent) {
            // A crash alarm must be heard: max out the alarm stream and put
            // it back afterwards.
            try {
                savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                audio.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                    0,
                )
            } catch (e: SecurityException) {
                savedAlarmVolume = null
            }
        }
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        if (uri != null) {
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(this@MainActivity, uri)
                    isLooping = urgent
                    prepare()
                    start()
                }
            } catch (e: Exception) {
                player?.release()
                player = null
            }
        }
        vibrate(urgent)
    }

    private fun stopAlarm() {
        player?.let {
            try {
                it.stop()
            } catch (e: IllegalStateException) {
                // Never started; nothing to stop.
            }
            it.release()
        }
        player = null
        vibrator().cancel()
        savedAlarmVolume?.let {
            try {
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
            } catch (e: SecurityException) {
                // Leave the volume as it is.
            }
        }
        savedAlarmVolume = null
    }

    private fun vibrate(urgent: Boolean) {
        val pattern = if (urgent) longArrayOf(0, 800, 400) else longArrayOf(0, 300, 150, 300, 150, 300)
        val repeat = if (urgent) 0 else -1
        val v = vibrator()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, repeat))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(pattern, repeat)
        }
    }

    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    /** "placed", "dialer" (no permission, or an emergency number) or "failed". */
    private fun placeCall(number: String?): String {
        if (number.isNullOrBlank()) return "failed"
        val uri = Uri.fromParts("tel", number, null)
        return try {
            if (hasCallPermission()) {
                // Android itself turns ACTION_CALL to an emergency number
                // into the dialer.
                startActivity(Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "placed"
            } else {
                startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "dialer"
            }
        } catch (e: ActivityNotFoundException) {
            "failed"
        } catch (e: SecurityException) {
            "failed"
        }
    }

    private fun hasCallPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED

    private fun requestCallPermission(result: MethodChannel.Result) {
        if (hasCallPermission()) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), CALL_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "rideguard/emergency"
        private const val CALL_PERMISSION_REQUEST = 4711
    }
}
