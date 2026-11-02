import Foundation

// probeReport writes the report the tray's Save a report writes into the --report folder, prints its
// path and first line, and exits 1 when LOCALAPPDATA is unset, since the report then has no log.
func probeReport(_ opts: ProbeOptions) -> Int32 {
    guard LogFile.shared != nil else {
        print("report: no LOCALAPPDATA")
        return 1
    }
    do {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: opts.report), withIntermediateDirectories: true)
        let app = App(store: Store(), minAspect: opts.minAspect)
        let file = try Report.save(app, in: opts.report)
        let first =
            (try? String(contentsOf: URL(fileURLWithPath: file), encoding: .utf8))?
            .split(separator: "\r\n").first.map(String.init) ?? ""
        print("report: \(file)")
        print("report first line: \(first)")
        return 0
    } catch {
        print("report: not written: \(error)")
        return 1
    }
}
