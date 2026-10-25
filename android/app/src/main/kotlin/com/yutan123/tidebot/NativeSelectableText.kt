package com.yutan123.tidebot

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.MetricAffectingSpan
import android.util.TypedValue
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt

class NativeSelectableTextFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val values = args as? Map<String, Any?> ?: emptyMap()
        return NativeSelectableTextView(context, viewId, messenger, values)
    }
}

private object BundledTextFonts {
    private val cache = mutableMapOf<String, Typeface>()
    fun get(context: Context, name: String): Typeface = cache.getOrPut(name) {
        val key = FlutterInjector.instance().flutterLoader()
            .getLookupKeyForAsset("assets/fonts/$name.ttf")
        Typeface.createFromAsset(context.assets, key)
    }
}

private class BundledTypefaceSpan(private val font: Typeface) : MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) { paint.typeface = font }
    override fun updateMeasureState(paint: TextPaint) { paint.typeface = font }
}

private class NativeSelectableTextView(
    context: Context, viewId: Int, messenger: BinaryMessenger, args: Map<String, Any?>,
) : PlatformView {
    private val channel = MethodChannel(messenger, "tidebot/native_selectable_text/$viewId")
    private val textView = TextView(context).apply {
        includeFontPadding = false
        setPadding(0, 0, 0, 0)
        setBackgroundColor(Color.TRANSPARENT)
        isVerticalScrollBarEnabled = false
        isHorizontalScrollBarEnabled = false
        setTextIsSelectable(true)
        isClickable = true
        isFocusable = true
        isFocusableInTouchMode = true
    }
    private var disposed = false
    private var nativeInteraction = false
    private var selectionActive = false
    private var selectionAtDown = false
    private var dragging = false
    private var downY = 0f
    private var lastY = 0f
    private var tracker: VelocityTracker? = null
    private var renderedFamily: String? = null
    private var renderedStyle: Int? = null
    private val density get() = textView.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    // Observe selection without replacing Android's menu or its standard actions.
    private val selectionObserver = object : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            selectionActive = true
            return true
        }
        override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
        override fun onActionItemClicked(mode: ActionMode, item: MenuItem) = false
        override fun onDestroyActionMode(mode: ActionMode) { selectionActive = false }
    }

    private fun sendDrag(phase: String, value: Float = 0f) {
        if (!disposed) channel.invokeMethod("scrollDrag", mapOf(
            "phase" to phase, "delta" to value / density, "velocity" to value / density,
        ))
    }

    private fun trackMovement(event: MotionEvent) {
        val sample = MotionEvent.obtain(event)
        sample.offsetLocation(event.rawX - event.x, event.rawY - event.y)
        tracker?.addMovement(sample)
        sample.recycle()
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        if (!nativeInteraction) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                tracker?.recycle()
                tracker = VelocityTracker.obtain()
                trackMovement(event)
                downY = event.rawY
                lastY = event.rawY
                selectionAtDown = selectionActive || textView.hasSelection()
                dragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                trackMovement(event)
                if (selectionAtDown || selectionActive || textView.hasSelection()) return false
                if (!dragging && abs(event.rawY - downY) > touchSlop) {
                    dragging = true
                    val cancel = MotionEvent.obtain(event)
                    cancel.action = MotionEvent.ACTION_CANCEL
                    textView.onTouchEvent(cancel)
                    cancel.recycle()
                    sendDrag("start")
                }
                if (dragging) {
                    sendDrag("update", event.rawY - lastY)
                    lastY = event.rawY
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val consumed = dragging
                if (dragging) {
                    trackMovement(event)
                    tracker?.computeCurrentVelocity(1000,
                        ViewConfiguration.get(textView.context).scaledMaximumFlingVelocity.toFloat())
                    if (event.actionMasked == MotionEvent.ACTION_UP) {
                        sendDrag("end", tracker?.yVelocity ?: 0f)
                    } else {
                        sendDrag("cancel")
                    }
                }
                dragging = false
                tracker?.recycle()
                tracker = null
                return consumed
            }
        }
        return false
    }

    init {
        textView.setOnTouchListener { _, event -> handleTouch(event) }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "update") {
                @Suppress("UNCHECKED_CAST")
                update(call.arguments as? Map<String, Any?> ?: emptyMap())
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        update(args)
    }

    private fun update(args: Map<String, Any?>) {
        nativeInteraction = args["nativeInteraction"] as? Boolean == true
        textView.customSelectionActionModeCallback = if (nativeInteraction) selectionObserver else null
        val fontSize = (args["fontSize"] as? Number)?.toFloat() ?: 14f
        val color = (args["color"] as? Number)?.toLong()?.toInt() ?: Color.BLACK
        val family = args["fontFamily"] as? String ?: "TideFont"
        val weight = (args["fontWeight"] as? Number)?.toInt() ?: 400
        val style = (if (weight >= 600) Typeface.BOLD else Typeface.NORMAL) or
            (if (args["italic"] as? Boolean == true) Typeface.ITALIC else Typeface.NORMAL)
        val base = when (family) {
            "LogMono", "LogSansSC" -> BundledTextFonts.get(textView.context, family)
            "monospace", "Courier" -> Typeface.MONOSPACE
            "TideFont" -> runCatching {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/fonts/TideFont-Regular.ttf")
                Typeface.createFromAsset(textView.context.assets, key)
            }.getOrElse { Typeface.SANS_SERIF }
            else -> Typeface.create(family, Typeface.NORMAL)
        }
        textView.typeface = Typeface.create(base, style)
        textView.setTextColor(color)
        textView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, fontSize)
        textView.letterSpacing = ((args["letterSpacing"] as? Number)?.toFloat() ?: 0f) / fontSize
        val text = args["text"] as? String ?: ""
        if (textView.text.toString() != text || renderedFamily != family || renderedStyle != style) {
            textView.text = if (family == "LogMono") {
                val styled = SpannableString(text)
                val chinese = Typeface.create(BundledTextFonts.get(textView.context, "LogSansSC"), style)
                // Explicit CJK spans avoid the device's customized Chinese face.
                var start = 0
                while (start < text.length) {
                    val useChinese = text[start].code > 0x024F
                    var end = start + 1
                    while (end < text.length && (text[end].code > 0x024F) == useChinese) end++
                    if (useChinese) styled.setSpan(BundledTypefaceSpan(chinese), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    start = end
                }
                styled
            } else text
            renderedFamily = family
            renderedStyle = style
        }
        textView.setLineSpacing(0f, (args["lineHeight"] as? Number)?.toFloat() ?: 1.2f)
        textView.gravity = Gravity.TOP or when (args["textAlign"] as? String) {
            "center" -> Gravity.CENTER_HORIZONTAL
            "right" -> Gravity.RIGHT
            "left" -> Gravity.LEFT
            "end" -> Gravity.END
            else -> Gravity.START
        }
        textView.textDirection = if (args["textDirection"] == "rtl")
            View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
        val density = textView.resources.displayMetrics.density
        val width = (args["width"] as? Number)?.toDouble() ?: return
        val revision = (args["revision"] as? Number)?.toInt() ?: 0
        // Native font fallback and line wrapping determine the actual height.
        textView.measure(
            View.MeasureSpec.makeMeasureSpec((width * density).roundToInt().coerceAtLeast(1), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val height = ceil(textView.measuredHeight / density.toDouble()).coerceAtLeast(1.0)
        textView.post {
            if (!disposed) channel.invokeMethod("heightChanged", mapOf(
                "revision" to revision, "width" to width, "height" to height,
            ))
        }
    }

    override fun getView(): View = textView
    override fun dispose() {
        if (dragging) sendDrag("cancel")
        tracker?.recycle()
        tracker = null
        textView.setOnTouchListener(null)
        textView.customSelectionActionModeCallback = null
        disposed = true
        channel.setMethodCallHandler(null)
    }
}
