package com.qxp.client

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    webView.settings.allowContentAccess = true
    webView.settings.allowFileAccess = true
    webView.settings.domStorageEnabled = true
    webView.settings.javaScriptCanOpenWindowsAutomatically = true
    webView.settings.mediaPlaybackRequiresUserGesture = false
  }
}
