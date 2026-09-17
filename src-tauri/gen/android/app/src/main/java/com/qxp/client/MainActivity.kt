package com.qxp.client

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  private var webViewRef: WebView? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    webViewRef = webView
    webView.settings.allowContentAccess = true
    webView.settings.allowFileAccess = true
    webView.settings.domStorageEnabled = true
    webView.settings.javaScriptCanOpenWindowsAutomatically = true
    webView.settings.mediaPlaybackRequiresUserGesture = false

    // Edge-to-edge: the WebView renders behind the status bar and the camera
    // cutout, but Android's WebView reports env(safe-area-inset-*) as 0, so
    // the frontend cannot compensate by itself. Forward the real insets into
    // the page; index.html's __lqxpSetSystemInsets turns them into CSS vars.
    ViewCompat.setOnApplyWindowInsetsListener(webView) { view, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars()
          or WindowInsetsCompat.Type.displayCutout()
      )
      pushInsets(bars.top, bars.bottom)
      insets
    }

    // The first inset dispatch can happen before the page finished loading, so
    // evaluateJavascript would silently do nothing: re-push a few times.
    for (delay in longArrayOf(0L, 750L, 1500L, 3000L, 5000L, 8000L)) {
      mainHandler.postDelayed({ pushCurrentInsets() }, delay)
    }
  }

  override fun onDestroy() {
    mainHandler.removeCallbacksAndMessages(null)
    webViewRef = null
    super.onDestroy()
  }

  private fun pushCurrentInsets() {
    val view = webViewRef ?: return
    val insets = ViewCompat.getRootWindowInsets(view) ?: return
    val bars = insets.getInsets(
      WindowInsetsCompat.Type.systemBars()
        or WindowInsetsCompat.Type.displayCutout()
    )
    pushInsets(bars.top, bars.bottom)
  }

  private fun pushInsets(top: Int, bottom: Int) {
    val view = webViewRef ?: return
    view.evaluateJavascript(
      "window.__lqxpSetSystemInsets && window.__lqxpSetSystemInsets($top, $bottom);",
      null
    )
  }
}
