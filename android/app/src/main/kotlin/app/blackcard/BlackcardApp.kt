package app.blackcard

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Pre-warms the Flutter engine when the process starts so that the side-button
 * double press shows the card immediately instead of waiting for a cold
 * engine boot. The engine outlives the Activity (which is torn down on every
 * close) for as long as Android keeps the process around.
 */
class BlackcardApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "main"
    }
}
