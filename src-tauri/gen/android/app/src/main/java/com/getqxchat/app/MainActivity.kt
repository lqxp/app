package com.getqxchat.app

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
    //
    // Keyboard: with decorFitsSystemWindows=false (edge-to-edge) Android
    // ignores windowSoftInputMode="adjustResize", so the WebView never
    // shrinks when the keyboard opens (window.innerHeight stays full height
    // and visualViewport may not move either). Forward the IME bottom inset
    // (physical px) through __lqxpSetKeyboardInset so the frontend can shrink
    // its own app shell (layout height - keyboard height) like adjustResize
    // would have done natively. Returning `insets` untouched keeps
    // propagation intact for the WebView and its children.
    ViewCompat.setOnApplyWindowInsetsListener(webView) { view, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars()
          or WindowInsetsCompat.Type.displayCutout()
      )
      val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
      pushInsets(bars.top, bars.bottom, ime.bottom)
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
    val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
    pushInsets(bars.top, bars.bottom, ime.bottom)
  }

  private fun pushInsets(top: Int, bottom: Int, imeBottom: Int = 0) {
    val view = webViewRef ?: return
    view.evaluateJavascript(
      "window.__lqxpSetSystemInsets && window.__lqxpSetSystemInsets($top, $bottom);" +
        "window.__lqxpSetKeyboardInset && window.__lqxpSetKeyboardInset($imeBottom);",
      null
    )
  }
}
