package com.qsw.rdesk

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityEvent

class RdeskAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        Companion.instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (Companion.instance === this) {
            Companion.instance = null
        }
        super.onDestroy()
    }

    fun performTap(normalizedX: Double, normalizedY: Double): Boolean {
        val screen = screenBounds()
        val x = screen.width * normalizedX.coerceIn(0.0, 1.0).toFloat()
        val y = screen.height * normalizedY.coerceIn(0.0, 1.0).toFloat()
        return dispatchPathGesture(
            path = tapPath(x, y),
            durationMs = 60,
        )
    }

    fun performAction(action: String): Boolean {
        return when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "scroll_up" -> performSwipe(0.5, 0.75, 0.5, 0.32)
            "scroll_down" -> performSwipe(0.5, 0.32, 0.5, 0.75)
            "delete" -> performDeleteLastChar()
            "enter" -> performEnter()
            else -> false
        }
    }

    fun performTextInput(text: String): Boolean {
        val node = findEditableNode(rootInActiveWindow) ?: return false
        return setNodeText(node, text)
    }

    fun performLongPress(normalizedX: Double, normalizedY: Double): Boolean {
        val screen = screenBounds()
        val x = screen.width * normalizedX.coerceIn(0.0, 1.0).toFloat()
        val y = screen.height * normalizedY.coerceIn(0.0, 1.0).toFloat()
        return dispatchPathGesture(
            path = tapPath(x, y),
            durationMs = 650,
        )
    }

    fun performDrag(
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        durationMs: Long = 0,
    ): Boolean {
        val screen = screenBounds()
        val sx = screen.width * startX.coerceIn(0.0, 1.0).toFloat()
        val sy = screen.height * startY.coerceIn(0.0, 1.0).toFloat()
        val ex = screen.width * endX.coerceIn(0.0, 1.0).toFloat()
        val ey = screen.height * endY.coerceIn(0.0, 1.0).toFloat()

        // Use quadratic bezier through midpoint for smooth gesture curve.
        val mx = (sx + ex) / 2f
        val my = (sy + ey) / 2f
        val path = Path().apply {
            moveTo(sx, sy)
            quadTo(mx, my, ex, ey)
        }

        // Dynamic duration: proportional to distance.
        // Longer = smoother, more reliably recognized as scroll by Android.
        val dist = Math.sqrt(((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy)).toDouble())
        val screenDiag = Math.sqrt((screen.width * screen.width + screen.height * screen.height).toDouble())
        val normalizedDist = dist / screenDiag
        // 250-600ms — smooth enough for Android scroll recognition
        val dur = if (durationMs > 0) durationMs else (250 + (normalizedDist * 400).toLong()).coerceIn(200, 700)
        return dispatchPathGesture(path = path, durationMs = dur)
    }

    fun performDragPath(
        points: List<Pair<Double, Double>>,
        durationMs: Long = 0,
    ): Boolean {
        if (points.size < 2) return false
        val screen = screenBounds()
        val w = screen.width
        val h = screen.height

        // Build smooth path using quadratic bezier curves between points.
        val path = Path().apply {
            val first = points[0]
            moveTo(
                (w * first.first.coerceIn(0.0, 1.0)).toFloat(),
                (h * first.second.coerceIn(0.0, 1.0)).toFloat(),
            )
            if (points.size == 2) {
                // Simple line for 2-point paths
                val last = points[1]
                lineTo(
                    (w * last.first.coerceIn(0.0, 1.0)).toFloat(),
                    (h * last.second.coerceIn(0.0, 1.0)).toFloat(),
                )
            } else {
                // Smooth curve through consecutive points using quadratic bezier
                for (i in 1 until points.size - 1) {
                    val p = points[i]
                    val pNext = points[i + 1]
                    val cx = (w * p.first.coerceIn(0.0, 1.0)).toFloat()
                    val cy = (h * p.second.coerceIn(0.0, 1.0)).toFloat()
                    val nx = (w * pNext.first.coerceIn(0.0, 1.0)).toFloat()
                    val ny = (h * pNext.second.coerceIn(0.0, 1.0)).toFloat()
                    // Control point is current, end point is midpoint to next
                    quadTo(cx, cy, (cx + nx) / 2f, (cy + ny) / 2f)
                }
                // Final segment to last point
                val last = points.last()
                lineTo(
                    (w * last.first.coerceIn(0.0, 1.0)).toFloat(),
                    (h * last.second.coerceIn(0.0, 1.0)).toFloat(),
                )
            }
        }
        // Compute total path length for duration
        var totalDist = 0.0
        for (i in 1 until points.size) {
            val dx = (points[i].first - points[i - 1].first) * w
            val dy = (points[i].second - points[i - 1].second) * h
            totalDist += Math.sqrt((dx * dx + dy * dy).toDouble())
        }
        val screenDiag = Math.sqrt((w * w + h * h).toDouble())
        val normalizedDist = totalDist / screenDiag
        // 250-800ms — longer for complex paths, smooth scrolling
        val dur = if (durationMs > 0) durationMs else (250 + (normalizedDist * 500).toLong()).coerceIn(200, 800)
        return dispatchPathGesture(path = path, durationMs = dur)
    }

    private fun performSwipe(
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
    ): Boolean {
        val screen = screenBounds()
        val path =
            Path().apply {
                moveTo(
                    screen.width * startX.coerceIn(0.0, 1.0).toFloat(),
                    screen.height * startY.coerceIn(0.0, 1.0).toFloat(),
                )
                lineTo(
                    screen.width * endX.coerceIn(0.0, 1.0).toFloat(),
                    screen.height * endY.coerceIn(0.0, 1.0).toFloat(),
                )
            }
        return dispatchPathGesture(path = path, durationMs = 220)
    }

    private fun screenBounds(): ScreenBounds {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            return ScreenBounds(
                width = bounds.width().coerceAtLeast(1).toFloat(),
                height = bounds.height().coerceAtLeast(1).toFloat(),
            )
        }

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        return ScreenBounds(
            width = metrics.widthPixels.coerceAtLeast(1).toFloat(),
            height = metrics.heightPixels.coerceAtLeast(1).toFloat(),
        )
    }

    private fun tapPath(x: Float, y: Float): Path =
        Path().apply {
            moveTo(x, y)
            lineTo(x + 0.1f, y + 0.1f)
        }

    private fun dispatchPathGesture(path: Path, durationMs: Long): Boolean {
        val gesture =
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
                .build()

        var dispatched = false
        val runnable = Runnable {
            dispatched =
                dispatchGesture(
                    gesture,
                    object : GestureResultCallback() {},
                    null,
                )
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run()
        } else {
            Handler(Looper.getMainLooper()).post(runnable)
        }
        return dispatched
    }

    private fun performDeleteLastChar(): Boolean {
        val node = findEditableNode(rootInActiveWindow) ?: return false
        val current = node.text?.toString() ?: return false
        if (current.isEmpty()) {
            return false
        }
        return setNodeText(node, current.dropLast(1))
    }

    private fun performEnter(): Boolean {
        val node = findEditableNode(rootInActiveWindow) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        }
        return false
    }

    private fun setNodeText(node: AccessibilityNodeInfo, text: String): Boolean {
        val args =
            Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text,
                )
            }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) {
            return null
        }
        if (node.isEditable && (node.isFocused || node.isAccessibilityFocused)) {
            return node
        }
        if (node.isEditable) {
            return node
        }
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            val found = findEditableNode(child)
            if (found != null) {
                return found
            }
        }
        return null
    }

    companion object {
        @Volatile var instance: RdeskAccessibilityService? = null
    }
}

private data class ScreenBounds(
    val width: Float,
    val height: Float,
)
