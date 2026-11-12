package app.blackcard

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
    private var picking = false
    private var awayInSettings = false

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = close()
    }

    override fun getCachedEngineId(): String = BlackcardApp.ENGINE_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Stay lit while waiting for the reader; the Dart-side timeout bounds this.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        requestHighestRefreshRate()
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
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
                    "cardPath" -> result.success(cardFile().takeIf { f -> f.exists() }?.absolutePath)
                    "pickCard" -> pickCard(result)
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
        // The engine is cached across launches, so tell Dart a fresh "session"
        // started: restart the timeout, recheck NFC and replay the card flick.
        if (!picking) channel?.invokeMethod("shown", null)
    }

    override fun onStop() {
        super.onStop()
        if (picking || isChangingConfigurations) return
        // Reset the Dart UI to its pre-animation state now, so the next launch
        // never flashes the last frame before the flick starts.
        channel?.invokeMethod("hidden", null)
        // Leaving the screen (home, app switch, Wallet's post-payment sheet)
        // ends the session -- except while our own picker or the NFC settings
        // page (opened from the "NFC is off" prompt) is on top.
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

    // ---- card image -------------------------------------------------------

    /** App-private storage: /data/data/app.blackcard/files/card */
    private fun cardFile() = File(filesDir, "card")

    private fun pickCard(result: MethodChannel.Result) {
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
            result.success(copyToPrivate(uri).absolutePath)
        } catch (e: Exception) {
            result.error("copy_failed", e.message, null)
        }
    }

    private fun copyToPrivate(uri: Uri): File {
        val tmp = File(filesDir, "card.tmp")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "cannot open image" }
            tmp.outputStream().use { input.copyTo(it) }
        }
        val dest = cardFile()
        if (!tmp.renameTo(dest)) {
            tmp.copyTo(dest, overwrite = true)
            tmp.delete()
        }
        return dest
    }

    companion object {
        private const val CHANNEL = "blackcard/native"
        private const val REQ_PICK = 4242
    }
}
