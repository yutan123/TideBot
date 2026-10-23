package com.yutan123.tidebot

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeSelectableTextFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val values = args as? Map<String, Any?> ?: emptyMap()
        return NativeSelectableTextView(context, values)
    }
}

private class NativeSelectableTextView(context: Context, args: Map<String, Any?>) : PlatformView {
    private val textView = TextView(context).apply {
        val fontSize = (args["fontSize"] as? Number)?.toFloat() ?: 14f
        val color = (args["color"] as? Number)?.toLong()?.toInt() ?: Color.BLACK
        val family = args["fontFamily"] as? String ?: ""
        val weight = (args["fontWeight"] as? Number)?.toInt() ?: 400
        val style = (if (weight >= 600) Typeface.BOLD else Typeface.NORMAL) or
            (if (args["italic"] as? Boolean == true) Typeface.ITALIC else Typeface.NORMAL)
        typeface = when (family) {
            "monospace", "Courier" -> Typeface.create("monospace", style)
            "TideFont" -> runCatching {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/fonts/TideFont-Regular.ttf")
                Typeface.createFromAsset(context.assets, key)
            }.getOrElse { Typeface.create("sans-serif", style) }
            else -> Typeface.create("sans-serif", style)
        }
        setTextColor(color)
        setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, fontSize)
        includeFontPadding = false
        setPadding(0, 0, 0, 0)
        setBackgroundColor(Color.TRANSPARENT)
        text = args["text"] as? String ?: ""
        setLineSpacing(0f, (args["lineHeight"] as? Number)?.toFloat() ?: 1f)
        gravity = when (args["textAlign"] as? String) {
            "center" -> Gravity.CENTER_HORIZONTAL
            "right", "end" -> Gravity.RIGHT
            else -> Gravity.LEFT
        }
        textDirection = when (args["textDirection"] as? String) {
            "rtl" -> View.TEXT_DIRECTION_RTL
            "ltr" -> View.TEXT_DIRECTION_LTR
            else -> View.TEXT_DIRECTION_FIRST_STRONG
        }
        setTextIsSelectable(true)
        isClickable = true
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun getView(): View = textView
    override fun dispose() = Unit
}