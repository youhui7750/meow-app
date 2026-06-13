package com.example.meow_food_butler

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
  private var sharedText: String? = null
  private var methodChannel: MethodChannel? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleSharedIntent(intent)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meow_food_butler/shared_text")
    methodChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getSharedText" -> result.success(sharedText)
        "shareInstagramStory" -> {
          val path = call.argument<String>("imagePath")
          val topColor = call.argument<String>("backgroundTopColor")
          val bottomColor = call.argument<String>("backgroundBottomColor")
          if (path == null) {
            result.error("INVALID_ARGUMENT", "imagePath is required", null)
          } else {
            result.success(shareInstagramStory(path, topColor, bottomColor))
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    handleSharedIntent(intent)
  }

  private fun handleSharedIntent(intent: Intent) {
    if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
      val text = intent.getStringExtra(Intent.EXTRA_TEXT)
      if (!text.isNullOrBlank()) {
        sharedText = text
        methodChannel?.invokeMethod("sharedText", text)
      }
    }
  }

  private fun shareInstagramStory(path: String, topColor: String?, bottomColor: String?): Boolean {
    val instagramPackage = "com.instagram.android"
    val file = File(path)
    if (!file.exists()) return false

    val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

    val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
      setDataAndType(uri, "image/png")
      putExtra("interactive_asset_uri", uri)
      putExtra("top_background_color", topColor)
      putExtra("bottom_background_color", bottomColor)
      putExtra("source_application", packageName)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      `package` = instagramPackage
    }

    return if (packageManager.resolveActivity(intent, 0) != null) {
      startActivity(intent)
      true
    } else {
      false
    }
  }
}


