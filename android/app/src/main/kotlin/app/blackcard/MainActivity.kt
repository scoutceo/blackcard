package app.blackcard

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The double-press screen. This app never handles payment data: Google Wallet
 * remains the default NFC payment service and answers the reader in the
 * background. This Activity only shows a picture and gets out of the way.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingPick: MethodChannel.Result? = null

    /** Our own photo picker is on top: don't end the session. */
    private var picking = false
    /** The keyguard bouncer is up because we asked for an unlock. */
    private var unlocking = false
    /** The user went to NFC settings from the "NFC is off" prompt. */
    private var awayInSettings = false
    /** Dart was told "hidden" (or never shown) and needs a "shown" on resume. */
    private var needsShow = true

    private val prefs by lazy { getSharedPreferences("blackcard", Context.MODE_PRIVATE) }
    private val keyguard by lazy { getSystemService(KeyguardManager::class.java) }

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = close()
    }

    override fun getCachedEngineId(): String = BlackcardApp.ENGINE_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Stay lit while waiting for the reader; the Dart-side timeout bounds this.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyShowWhenLocked()
        requestHighestRefreshRate()
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    /**
     * Appear straight over the lock screen, like Apple Pay. Only the card
     * picture is visible while locked; Google Wallet still asks for an unlock
     * to pay, and anything that changes settings requires one too.
     */
    private fun applyShowWhenLocked() {
        setShowWhenLocked(prefs.getBoolean(PREF_LOCK_SCREEN, true))
    }

    /** Ask for the panel's fastest mode (120 Hz on the S26) so the card flick is smooth. */
    private fun requestHighestRefreshRate() {
        val display = (if (Build.VERSION.SDK_INT >= 30) display else null)
            ?: @Suppress("DEPRECATION") windowManager.defaultDisplay
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.also { it.preferredDisplayModeId = best.modeId }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "cardPath" -> result.success(cardFile().existingPath())
                    "sourcePath" -> result.success(sourceFile().existingPath())
                    "pickImage" -> pickImage(result)
                    "saveCard" -> saveCard(call.arguments as ByteArray, result)
                    "settings" -> result.success(
                        mapOf(
                            "timeoutSeconds" to prefs.getInt(PREF_TIMEOUT, 60),
                            "showOnLockScreen" to prefs.getBoolean(PREF_LOCK_SCREEN, true),
                        )
                    )
                    "setTimeout" -> {
                        prefs.edit().putInt(PREF_TIMEOUT, call.arguments as Int).apply()
                        result.success(null)
                    }
                    "setShowOnLockScreen" -> {
                        prefs.edit().putBoolean(PREF_LOCK_SCREEN, call.arguments as Boolean).apply()
                        applyShowWhenLocked()
                        result.success(null)
                    }
                    "isLocked" -> result.success(keyguard.isKeyguardLocked)
                    "unlock" -> unlock(result)
                    "nfcEnabled" -> result.success(NfcAdapter.getDefaultAdapter(this)?.isEnabled == true)
                    "openNfcSettings" -> {
                        awayInSettings = true
                        startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        result.success(null)
                    }
                    "close" -> { result.success(null); close() }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        awayInSettings = false
        // The engine is cached across launches, so tell Dart a fresh session
        // started: restart the timeout, recheck NFC and replay the card flick.
        // Not after our own picker or unlock prompt -- that's the same session.
        if (needsShow) {
            needsShow = false
            channel?.invokeMethod("shown", null)
        }
    }

    override fun onStop() {
        super.onStop()
        if (picking || unlocking || isChangingConfigurations) return
        // Reset the Dart UI to its pre-animation state now, so the next launch
        // never flashes the last frame before the flick starts.
        channel?.invokeMethod("hidden", null)
        needsShow = true
        // Leaving the screen (home, app switch, Wallet's post-payment sheet)
        // ends the session, unless it's the NFC settings page we opened.
        if (!awayInSettings) close()
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(screenOff) }
        pendingPick?.success(null)
        pendingPick = null
        super.onDestroy()
    }

    private fun close() {
        if (!isFinishing) finishAndRemoveTask()
    }

    // ---- unlock -----------------------------------------------------------

    private fun unlock(result: MethodChannel.Result) {
        if (!keyguard.isKeyguardLocked) {
            result.success(true)
            return
        }
        unlocking = true
        keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() { unlocking = false; result.success(true) }
            override fun onDismissCancelled() { unlocking = false; result.success(false) }
            override fun onDismissError() { unlocking = false; result.success(false) }
        })
    }

    // ---- card image -------------------------------------------------------
    //
    // Both files live in app-private storage (/data/data/app.blackcard/files):
    //   card_source  the image as picked, kept so the crop can be re-adjusted
    //   card         the cropped card shown on screen

    private fun cardFile() = File(filesDir, "card")
    private fun sourceFile() = File(filesDir, "card_source")
    private fun File.existingPath() = takeIf { it.exists() }?.absolutePath

    /** Lets the user choose an image; returns the path of a private copy (not yet the card). */
    private fun pickImage(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "picker already open", null)
            return
        }
        // System photo picker: needs no storage permission and grants access
        // to only the single image the user chooses.
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*")
        }
        pendingPick = result
        picking = true
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_PICK)
    }

    @Deprecated("FlutterActivity is not a ComponentActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK) return
        picking = false
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            result.success(copyToPrivate(uri, File(filesDir, "card_pick")).absolutePath)
        } catch (e: Exception) {
            result.error("copy_failed", e.message, null)
        }
    }

    /**
     * Dart hands back the cropped card as PNG bytes. Only now does the picked
     * image become the source, so cancelling the crop keeps the old card.
     */
    private fun saveCard(png: ByteArray, result: MethodChannel.Result) {
        try {
            File(filesDir, "card_pick").takeIf { it.exists() }?.let { replace(it, sourceFile()) }
            val tmp = File(filesDir, "card.tmp").apply { writeBytes(png) }
            replace(tmp, cardFile())
            result.success(cardFile().absolutePath)
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    private fun copyToPrivate(uri: Uri, dest: File): File {
        val tmp = File(filesDir, "${dest.name}.tmp")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "cannot open image" }
            tmp.outputStream().use { input.copyTo(it) }
        }
        replace(tmp, dest)
        return dest
    }

    private fun replace(from: File, to: File) {
        if (!from.renameTo(to)) {
            from.copyTo(to, overwrite = true)
            from.delete()
        }
    }

    companion object {
        private const val CHANNEL = "blackcard/native"
        private const val REQ_PICK = 4242
        private const val PREF_TIMEOUT = "timeoutSeconds"
        private const val PREF_LOCK_SCREEN = "showOnLockScreen"
    }
}
