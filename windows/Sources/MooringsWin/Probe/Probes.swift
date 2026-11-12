import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// Probe runs one mechanism, prints lines the Windows workflow checks, and returns the exit code.
typealias Probe = @Sendable (ProbeOptions) -> Int32

// probes maps each probe name to its function.
let probes: [String: Probe] = [
    "version": probeVersion,
    "console": probeConsole,
    "link": probeLink,
    "buttons": probeButtons,
    "captions": probeCaptions,
    "nativeclicks": probeNativeClicks,
    "monitors": probeMonitors,
    "modes": probeModes,
    "list": probeList,
    "place": probePlace,
    "moor": probeMoor,
    "host": probeHost,
    "nudge": probeNudge,
    "events": probeEvents,
    "menu": probeMenu,
    "pointermenu": probePointerMenu,
    "tray": probeTray,
    "hotkeys": probeHotkeys,
    "altgr": probeAltGr,
    "hold": probeHold,
    "banner": probeBanner,
    "skip": probeSkip,
    "login": probeLogin,
    "quit": probeQuit,
    "drag": probeDrag,
    "stash": probeStash,
    "organize": probeOrganize,
    "sizes": probeSizes,
    "tiling": probeTiling,
    "badge": probeBadge,
    "workspace": probeWorkspace,
    "apprule": probeAppRule,
    "footprint": probeFootprint,
    "stand": probeStand,
    "contracts": probeContracts,
    "scenarios": probeScenarios,
    "update": probeUpdate,
    "soak": probeSoak,
    "report": probeReport,
]
