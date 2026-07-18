package com.qxp.client

import android.os.Bundle
import android.view.Window
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    requestWindowFeature(Window.FEATURE_NO_TITLE)
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    actionBar?.hide()
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
