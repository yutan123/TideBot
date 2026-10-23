package com.yutan123.tidebot

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
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

    init {
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
        val fontSize = (args["fontSize"] as? Number)?.toFloat() ?: 14f
        val color = (args["color"] as? Number)?.toLong()?.toInt() ?: Color.BLACK
        val family = args["fontFamily"] as? String ?: "TideFont"
        val weight = (args["fontWeight"] as? Number)?.toInt() ?: 400
        val style = (if (weight >= 600) Typeface.BOLD else Typeface.NORMAL) or
            (if (args["italic"] as? Boolean == true) Typeface.ITALIC else Typeface.NORMAL)
        val base = when (family) {
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
        if (textView.text.toString() != text) textView.text = text
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
        disposed = true
        channel.setMethodCallHandler(null)
    }
}
