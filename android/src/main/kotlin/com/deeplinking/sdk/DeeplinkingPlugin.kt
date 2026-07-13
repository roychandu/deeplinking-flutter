package com.deeplinking.sdk

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.NewIntentListener
import android.view.ViewTreeObserver
import android.util.Log

class DeeplinkingPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, NewIntentListener {
    private lateinit var channel : MethodChannel
    private var activity: Activity? = null
    private var context: Context? = null
    private var focusChangeListener: ViewTreeObserver.OnWindowFocusChangeListener? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "deeplinking_sdk_channel")
        channel.setMethodCallHandler(this)
        Log.d("DeeplinkingPlugin", "Plugin attached to engine.")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getClipboardText") {
            val text = getClipboardText()
            result.success(text)
        } else {
            result.notImplemented()
        }
    }

    private fun getClipboardText(): String {
        val clipboard = context?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        return try {
            if (clipboard != null && clipboard.hasPrimaryClip()) {
                clipboard.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
            } else {
                ""
            }
        } catch (e: Exception) {
            ""
        }
    }

    private fun checkClipboardAndNotify() {
        val text = getClipboardText()
        if (text.isNotEmpty()) {
            Log.d("DeeplinkingPlugin", "Clipboard data detected natively: $text")
            channel.invokeMethod("onClipboardData", mapOf("text" to text))
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        Log.d("DeeplinkingPlugin", "Attached to activity: $activity. Checking cold start intent.")
        
        // Handle cold start intent
        handleIntent(activity?.intent, "cold")
        setupFocusListener()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        cleanupFocusListener()
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        setupFocusListener()
    }

    override fun onDetachedFromActivity() {
        cleanupFocusListener()
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        Log.d("DeeplinkingPlugin", "onNewIntent warm start triggered.")
        handleIntent(intent, "warm")
        return false
    }

    private fun handleIntent(intent: Intent?, appState: String) {
        val uri = intent?.data ?: return
        if (uri.scheme != "https" && uri.scheme != "storeroom") return

        Log.d("DeeplinkingPlugin", "handleIntent URI: $uri ($appState)")

        val isProductScheme = uri.scheme == "storeroom" && uri.host == "product"
        val trackingLinkId = if (isProductScheme) null else uri.pathSegments.lastOrNull()
        val screen = if (isProductScheme) {
            "ProductDetail"
        } else {
            uri.getQueryParameter("screen")
        }
        val productId = uri.getQueryParameter("productId")
            ?: uri.getQueryParameter("product_id")
            ?: if (isProductScheme) uri.pathSegments.firstOrNull() else null
        val referralCode = uri.getQueryParameter("ref")
            ?: uri.getQueryParameter("referralCode")
        val shareId = uri.getQueryParameter("shareId") ?: uri.getQueryParameter("share_id")

        if (screen != null && screen.isNotEmpty()) {
            val flutterPrefs = context?.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            flutterPrefs?.edit()?.apply {
                putString("flutter.deep_link_screen", screen)
                putString("flutter.deep_link_product_id", productId ?: "")
                apply()
            }

            channel.invokeMethod(
                "openDeepLink",
                mapOf(
                    "screen" to screen,
                    "productId" to (productId ?: ""),
                    "linkId" to (trackingLinkId ?: ""),
                    "appState" to appState,
                    "referralCode" to (referralCode ?: ""),
                    "shareId" to (shareId ?: "")
                )
            )
            Log.d("DeeplinkingPlugin", "Intent link pushed to Dart: screen=$screen, productId=$productId")
        }

        // Prevent the same intent from triggering again
        intent.data = null
    }

    private fun setupFocusListener() {
        val act = activity ?: return
        focusChangeListener = ViewTreeObserver.OnWindowFocusChangeListener { hasFocus ->
            if (hasFocus) {
                Log.d("DeeplinkingPlugin", "Activity window focus changed: hasFocus=true. Checking clipboard.")
                checkClipboardAndNotify()
            }
        }
        act.window.decorView.viewTreeObserver.addOnWindowFocusChangeListener(focusChangeListener)
    }

    private fun cleanupFocusListener() {
        val act = activity ?: return
        val listener = focusChangeListener ?: return
        try {
            act.window.decorView.viewTreeObserver.removeOnWindowFocusChangeListener(listener)
        } catch (e: Exception) {
            // Ignore if already removed
        }
        focusChangeListener = null
    }
}
