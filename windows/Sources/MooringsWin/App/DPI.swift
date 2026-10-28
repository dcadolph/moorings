import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// perMonitorAwareV2 is DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, a cast macro Swift does not
// import.
var perMonitorAwareV2: DPI_AWARENESS_CONTEXT? { DPI_AWARENESS_CONTEXT(bitPattern: -4) }
