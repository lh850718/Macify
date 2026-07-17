package com.huxizen.huxi_zen

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "huxi_zen/platform_capabilities",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilityReport" -> result.success(capabilityReport())
                "pulseHaptic" -> result.success(pulseHaptic())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "huxi_zen/background_audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(startBackgroundAudio(call.arguments))
                "sync" -> result.success(syncBackgroundAudio(call.arguments))
                "stop" -> result.success(stopBackgroundAudio())
                "startHapticPattern" -> result.success(startHapticPattern(call.arguments))
                "stopHaptics" -> result.success(stopBackgroundHaptics())
                "playCompletionHaptic" -> result.success(playCompletionHaptic())
                "status" -> result.success(backgroundAudioStatus())
                else -> result.notImplemented()
            }
        }
    }

    private fun capabilityReport(): Map<String, Any?> {
        val vibrator = vibrator()
        return mapOf(
            "platform" to "android",
            "osVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "backgroundAudioModeDeclared" to hasPermission(Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK),
            "foregroundServicePermissionDeclared" to hasPermission(Manifest.permission.FOREGROUND_SERVICE),
            "mediaPlaybackForegroundServicePermissionDeclared" to hasPermission(
                Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK,
            ),
            "wakeLockPermissionDeclared" to hasPermission(Manifest.permission.WAKE_LOCK),
            "mediaSessionServiceDeclared" to isServiceDeclared(BackgroundAudioService::class.java),
            "postNotificationsPermissionDeclared" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                hasPermission(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                true
            },
            "vibrationPermissionDeclared" to hasPermission(Manifest.permission.VIBRATE),
            "hapticsAvailable" to (vibrator?.hasVibrator() == true),
            "vibrationAvailable" to (vibrator?.hasVibrator() == true),
            "amplitudeControlAvailable" to (vibrator?.hasAmplitudeControl() == true),
            "backgroundVibrationRequiresForegroundService" to true,
            "notes" to listOf(
                "Android background audio will require a MediaSession foreground service for production.",
                "Android background vibration must be tested behind a foreground service and user-visible notification.",
            ),
        )
    }

    private fun startBackgroundAudio(arguments: Any?): Boolean {
        return sendBackgroundAudioIntent(arguments, sync = false)
    }

    private fun syncBackgroundAudio(arguments: Any?): Boolean {
        return sendBackgroundAudioIntent(arguments, sync = true)
    }

    private fun sendBackgroundAudioIntent(arguments: Any?, sync: Boolean): Boolean {
        val args = arguments as? Map<*, *> ?: return false
        val tracksJson = args["tracksJson"] as? String ?: return false
        if (tracksJson.isBlank() || !isServiceDeclared(BackgroundAudioService::class.java)) {
            return false
        }

        val intent = if (sync) {
            BackgroundAudioService.syncIntent(this, tracksJson)
        } else {
            BackgroundAudioService.startIntent(this, tracksJson)
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                @Suppress("DEPRECATION")
                startService(intent)
            }
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun stopBackgroundAudio(): Boolean {
        val intent = Intent(this, BackgroundAudioService::class.java).apply {
            action = BackgroundAudioService.ACTION_STOP
        }
        return try {
            startService(intent)
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun startHapticPattern(arguments: Any?): Boolean {
        val args = arguments as? Map<*, *> ?: return false
        val patternJson = args["patternJson"] as? String ?: return false
        if (patternJson.isBlank() || !isServiceDeclared(BackgroundAudioService::class.java)) {
            return false
        }

        return try {
            startService(BackgroundAudioService.startHapticsIntent(this, patternJson))
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun stopBackgroundHaptics(): Boolean {
        return try {
            startService(BackgroundAudioService.stopHapticsIntent(this))
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun backgroundAudioStatus(): Map<String, Any?> {
        val status = BackgroundAudioService.status().toMutableMap()
        status["platform"] = "android"
        status["mediaSessionServiceDeclared"] =
            isServiceDeclared(BackgroundAudioService::class.java)
        return status
    }

    private fun pulseHaptic(): Boolean {
        val vibrator = vibrator() ?: return false
        if (!hasPermission(Manifest.permission.VIBRATE) || !vibrator.hasVibrator()) return false

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        45,
                        VibrationEffect.DEFAULT_AMPLITUDE,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(45)
            }
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun playCompletionHaptic(): Boolean {
        val vibrator = vibrator() ?: return false
        if (!hasPermission(Manifest.permission.VIBRATE) || !vibrator.hasVibrator()) return false

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createWaveform(
                        longArrayOf(0, 380, 220, 380),
                        intArrayOf(0, 255, 0, 255),
                        -1,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 380, 220, 380), -1)
            }
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return try {
            val flags = PackageManager.GET_PERMISSIONS
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(flags.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, flags)
            }
            info.requestedPermissions?.contains(permission) == true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun isServiceDeclared(serviceClass: Class<*>): Boolean {
        return try {
            val component = ComponentName(this, serviceClass)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getServiceInfo(
                    component,
                    PackageManager.ComponentInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getServiceInfo(component, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}
