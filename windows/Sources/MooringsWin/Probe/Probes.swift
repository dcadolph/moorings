import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// version is the build's version, shown by the version probe and, later, the tray's About item.
let version = "dev"

// Probe runs one mechanism, prints lines the Windows workflow checks, and returns the exit code.
typealias Probe = @Sendable (ProbeOptions) -> Int32

// probes maps each probe name to its function.
let probes: [String: Probe] = [
    "version": probeVersion,
    "monitors": probeMonitors,
    "modes": probeModes,
    "list": probeList,
    "place": probePlace,
    "moor": probeMoor,
    "nudge": probeNudge,
    "events": probeEvents,
    "menu": probeMenu,
    "tray": probeTray,
    "hotkeys": probeHotkeys,
    "hold": probeHold,
    "banner": probeBanner,
    "skip": probeSkip,
    "lift": probeLift,
    "chain": probeChain,
    "reload": probeReload,
    "actions": probeActions,
    "login": probeLogin,
    "quit": probeQuit,
    "drag": probeDrag,
    "footprint": probeFootprint,
    "stand": probeStand,
    "contracts": probeContracts,
]
