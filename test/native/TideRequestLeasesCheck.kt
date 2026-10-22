package com.yutan123.tidebot

/** Standalone regression checks: compile with TideRequestLeases.kt and run on the JVM. */
fun main() {
    var time = 0L
    val leases = TideRequestLeases { time }
    check(!leases.hasActive())
    leases.begin("first")
    leases.begin("second")
    leases.end("first")
    check(leases.hasActive()) // One request finishing cannot stop another.
    leases.end("second")
    check(!leases.hasActive())
    leases.end("second")
    check(!leases.hasActive()) // Duplicate release is harmless.
    leases.begin("crashed-engine")
    time = 600_000L
    check(!leases.hasActive()) // Lost engines cannot keep the service alive.
    leases.renew("crashed-engine")
    check(!leases.hasActive()) // Renewal cannot recreate a released/expired lease.
    leases.begin("long-request")
    time += 540_000L
    leases.renew("long-request")
    time += 540_000L
    check(leases.hasActive())
    time += 60_000L
    check(!leases.hasActive())
    println("8 native request-lease regression checks passed")
}