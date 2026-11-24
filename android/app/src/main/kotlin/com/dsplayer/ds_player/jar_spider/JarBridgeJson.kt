package com.dsplayer.ds_player.jar_spider

import org.json.JSONArray
import org.json.JSONObject

internal object JarBridgeJson {
    fun encodeRequest(method: String, arguments: Any?): String {
        return JSONObject().apply {
            put("method", method)
            put("arguments", wrap(arguments ?: emptyMap<String, Any?>()))
        }.toString()
    }

    fun decodeObject(value: String): Map<String, Any?> {
        val json = JSONObject(value)
        val result = LinkedHashMap<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = unwrap(json.opt(key))
        }
        return result
    }

    fun encodeSuccess(data: Any?): String {
        return JSONObject().apply {
            put("ok", true)
            put("data", wrap(data))
        }.toString()
    }

    fun encodeBridgeResult(result: Map<*, *>): String {
        val json = JSONObject()
        result.forEach { (key, value) ->
            if (key != null) {
                json.put(key.toString(), wrap(value))
            }
        }
        return json.toString()
    }

    fun encodeFailure(
        kind: String,
        message: String,
        stack: String? = null,
    ): String {
        return JSONObject().apply {
            put("ok", false)
            put("errorKind", kind)
            put("error", message)
            if (!stack.isNullOrBlank()) {
                put("stack", stack)
            }
        }.toString()
    }

    private fun unwrap(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> {
                val map = LinkedHashMap<String, Any?>()
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = unwrap(value.opt(key))
                }
                map
            }

            is JSONArray -> {
                val list = ArrayList<Any?>(value.length())
                for (index in 0 until value.length()) {
                    list.add(unwrap(value.opt(index)))
                }
                list
            }

            else -> value
        }
    }

    private fun wrap(value: Any?): Any {
        return when (value) {
            null -> JSONObject.NULL
            is JSONObject, is JSONArray -> value
            is Map<*, *> -> JSONObject().apply {
                value.forEach { (key, item) ->
                    if (key != null) {
                        put(key.toString(), wrap(item))
                    }
                }
            }

            is Iterable<*> -> JSONArray().apply {
                value.forEach { item -> put(wrap(item)) }
            }

            is Array<*> -> JSONArray().apply {
                value.forEach { item -> put(wrap(item)) }
            }

            is Boolean,
            is Number,
            is String -> value

            else -> value.toString()
        }
    }
}
