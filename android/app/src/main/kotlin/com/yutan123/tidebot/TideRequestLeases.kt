package com.yutan123.tidebot

/** Per-request ownership, shared by the Activity and service. Uses monotonic time. */
internal class TideRequestLeases(private val now: () -> Long) {
    private val deadlines = mutableMapOf<String, Long>()
    @Synchronized fun begin(id: String) {
        require(id.isNotBlank())
        deadlines[id] = now() + 10 * 60_000L
    }
    @Synchronized fun renew(id: String) {
        val time = now()
        if ((deadlines[id] ?: 0L) > time) deadlines[id] = time + 10 * 60_000L
        else deadlines.remove(id)
    }
    @Synchronized fun end(id: String) { deadlines.remove(id) }
    @Synchronized fun hasActive(): Boolean {
        val time = now()
        deadlines.entries.removeAll { it.value <= time }
        return deadlines.isNotEmpty()
    }
}
