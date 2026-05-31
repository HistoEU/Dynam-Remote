package eu.histo.dynamremote

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.text.InputType
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlin.math.roundToInt

class MainActivity : Activity() {
    private lateinit var prefs: SharedPreferences
    private lateinit var root: LinearLayout
    private lateinit var connectionPanel: LinearLayout
    private lateinit var recentContainer: LinearLayout
    private lateinit var hostInput: EditText
    private lateinit var statusText: TextView
    private lateinit var webView: WebView
    private lateinit var disconnectButton: Button
    private lateinit var hostsButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = getSharedPreferences("dynam_remote_shell", Context.MODE_PRIVATE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        buildLayout()
        configureWebView()
        renderRecentHosts()

        intent?.dataString
            ?.let(::normalizeHostUrl)
            ?.let { hostUrl ->
                hostInput.setText(hostUrl)
                openHost(hostUrl)
            }
    }

    private fun buildLayout() {
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(8, 10, 14))
            setOnApplyWindowInsetsListener { view, insets ->
                view.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom
                )
                insets
            }
        }

        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(12.dp(), 10.dp(), 12.dp(), 10.dp())
            setBackgroundColor(Color.rgb(18, 23, 34))
        }

        statusText = TextView(this).apply {
            text = "Dynam Remote"
            textSize = 16f
            setTextColor(Color.WHITE)
            setSingleLine(true)
        }
        toolbar.addView(
            statusText,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )

        hostsButton = Button(this).apply {
            text = "Hosts"
            setOnClickListener {
                haptic()
                connectionPanel.visibility =
                    if (connectionPanel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            }
        }
        toolbar.addView(hostsButton)

        disconnectButton = Button(this).apply {
            text = "Stop"
            isEnabled = false
            setOnClickListener {
                haptic()
                requestBrowserDisconnect()
            }
        }
        toolbar.addView(disconnectButton)

        connectionPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16.dp(), 16.dp(), 16.dp(), 12.dp())
            setBackgroundColor(Color.rgb(8, 10, 14))
        }

        hostInput = EditText(this).apply {
            hint = "http://192.168.1.10:4317"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            setSingleLine(true)
        }
        connectionPanel.addView(
            hostInput,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val openButton = Button(this).apply {
            text = "Open Host"
            setOnClickListener {
                haptic()
                val normalized = normalizeHostUrl(hostInput.text.toString())
                if (normalized == null) {
                    statusText.text = "Enter a valid host URL"
                    return@setOnClickListener
                }
                openHost(normalized)
            }
        }
        connectionPanel.addView(openButton)

        val recentTitle = TextView(this).apply {
            text = "Recent hosts"
            textSize = 14f
            setTextColor(Color.rgb(170, 180, 196))
            setPadding(0, 12.dp(), 0, 4.dp())
        }
        connectionPanel.addView(recentTitle)

        recentContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        connectionPanel.addView(recentContainer)

        webView = WebView(this).apply {
            visibility = View.GONE
        }

        root.addView(
            toolbar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        root.addView(
            connectionPanel,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        root.addView(
            webView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )

        setContentView(root)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        WebView.setWebContentsDebuggingEnabled(debuggable)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            allowFileAccess = false
            allowContentAccess = false
            userAgentString = "$userAgentString DynamRemoteAndroidShell/0.1"
        }
        webView.isFocusable = true
        webView.isFocusableInTouchMode = true

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread { request.deny() }
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                val uri = request.url
                val scheme = uri.scheme ?: return false
                if (scheme == "http" || scheme == "https") return false
                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    true
                } catch (_: Exception) {
                    true
                }
            }

            override fun onPageFinished(view: WebView, url: String?) {
                statusText.text = displayHost(url ?: "")
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError
            ) {
                if (request.isForMainFrame) {
                    statusText.text = error.description?.toString() ?: "Host unavailable"
                    connectionPanel.visibility = View.VISIBLE
                }
            }
        }
    }

    private fun openHost(hostUrl: String) {
        saveRecentHost(hostUrl)
        renderRecentHosts()
        connectionPanel.visibility = View.GONE
        webView.visibility = View.VISIBLE
        disconnectButton.isEnabled = true
        statusText.text = displayHost(hostUrl)
        webView.loadUrl(hostUrl)
        webView.requestFocus()
    }

    private fun requestBrowserDisconnect() {
        if (webView.visibility != View.VISIBLE) return
        val script = """
            (function() {
              var buttons = Array.prototype.slice.call(document.querySelectorAll('button'));
              var target = document.getElementById('disconnectBtn') ||
                buttons.find(function(button) {
                  return /stop|disconnect/i.test(button.textContent || '');
                });
              if (target) {
                target.click();
                return 'clicked';
              }
              return 'missing';
            })();
        """.trimIndent()
        webView.evaluateJavascript(script) { result ->
            if (result?.contains("missing") == true) {
                Toast.makeText(this, "Use the controller Stop control after pairing.", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun normalizeHostUrl(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return null
        val withScheme = if (trimmed.contains("://")) trimmed else "http://$trimmed"
        val uri = Uri.parse(withScheme)
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        if (uri.host.isNullOrBlank()) return null
        return if (uri.encodedPath.isNullOrBlank()) {
            uri.buildUpon().encodedPath("/").build().toString()
        } else {
            uri.toString()
        }
    }

    private fun saveRecentHost(hostUrl: String) {
        val next = listOf(hostUrl)
            .plus(recentHosts().filterNot { it.equals(hostUrl, ignoreCase = true) })
            .take(6)
        prefs.edit().putString("recent_hosts", next.joinToString("\n")).apply()
    }

    private fun recentHosts(): List<String> {
        return prefs.getString("recent_hosts", "")
            .orEmpty()
            .lineSequence()
            .map(String::trim)
            .filter(String::isNotBlank)
            .toList()
    }

    private fun renderRecentHosts() {
        recentContainer.removeAllViews()
        val hosts = recentHosts()
        if (hosts.isEmpty()) {
            recentContainer.addView(TextView(this).apply {
                text = "No saved hosts"
                setTextColor(Color.rgb(170, 180, 196))
            })
            return
        }
        hosts.forEach { hostUrl ->
            recentContainer.addView(Button(this).apply {
                text = displayHost(hostUrl)
                setOnClickListener {
                    haptic()
                    openHost(hostUrl)
                }
            })
        }
    }

    private fun displayHost(url: String): String {
        val uri = Uri.parse(url)
        val host = uri.host ?: return if (url.isBlank()) "Dynam Remote" else url
        val hostLabel = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
        val port = if (uri.port > 0) ":${uri.port}" else ""
        return "${uri.scheme ?: "http"}://$hostLabel$port"
    }

    private fun haptic() {
        root.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
    }

    private fun Int.dp(): Int = (this * resources.displayMetrics.density).roundToInt()

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        when {
            connectionPanel.visibility == View.VISIBLE && webView.visibility == View.VISIBLE -> {
                connectionPanel.visibility = View.GONE
            }
            webView.visibility == View.VISIBLE && webView.canGoBack() -> {
                webView.goBack()
            }
            webView.visibility == View.VISIBLE -> {
                connectionPanel.visibility = View.VISIBLE
            }
            else -> {
                super.onBackPressed()
            }
        }
    }

    override fun onPause() {
        webView.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }
}
