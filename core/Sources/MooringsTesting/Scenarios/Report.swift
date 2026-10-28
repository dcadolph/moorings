import Foundation

// ScenarioReport is one run of the scenarios on one host, written as report.json and report.html.
public struct ScenarioReport: Equatable, Sendable, Codable {
    // host names the platform the scenarios ran on.
    public var host: String
    // results lists each scenario's result in the order they ran.
    public var results: [ScenarioResult]

    // init builds a report of results on host.
    public init(host: String, results: [ScenarioResult]) {
        self.host = host
        self.results = results
    }

    // failures lists every rule broken, scenario by scenario.
    public var failures: [ScenarioFailure] { results.flatMap(\.failures) }

    // summary is the line a run ends with, the line the workflow checks.
    public var summary: String {
        let skipped = results.filter { $0.skipped != nil }.count
        let ran = results.count - skipped
        let failed = results.filter { !$0.passed }.count
        return "scenarios: \(ran) run, " + (skipped > 0 ? "\(skipped) skipped, " : "") + "\(failed) failed"
    }

    // json writes the report as indented JSON with sorted keys.
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    // write saves report.json and report.html in dir.
    public func write(to dir: URL) throws {
        try json().write(to: dir.appendingPathComponent("report.json"))
        try Data(html().utf8).write(to: dir.appendingPathComponent("report.html"))
    }

    // html writes the report as one page: a sidebar of the scenarios, then each with its rules,
    // numbers, frames and picture.
    public func html() -> String {
        let nav = results.map { r in
            "<li><a href=\"javascript:void(0)\" data-jump=\"\(esc(r.name))\">\(mark(r)) \(esc(r.name))</a></li>"
        }.joined(separator: "\n")
        let sections = results.map(section).joined(separator: "\n")
        return """
            <!doctype html>
            <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
            <title>Moorings scenarios</title>
            <style>
            :root { --bg: #fff; --fg: #1d1f21; --dim: #5a5f66; --line: #d8dbe0; --ok: #1a7f37; --bad: #c62828; }
            @media (prefers-color-scheme: dark) {
              :root { --bg: #16181b; --fg: #e6e8eb; --dim: #a0a6ad; --line: #33373c; --ok: #4ac26b; --bad: #ff6b6b; }
            }
            body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.5 system-ui, sans-serif; }
            nav { position: sticky; top: 0; float: left; width: 300px; height: 100vh; overflow: auto;
              border-right: 1px solid var(--line); padding: 16px; box-sizing: border-box; }
            nav ul { list-style: none; padding: 0; }
            nav a { color: var(--fg); text-decoration: none; }
            main { margin-left: 300px; padding: 16px 24px; }
            section { border-bottom: 1px solid var(--line); padding-bottom: 16px; }
            .ok { color: var(--ok); } .bad { color: var(--bad); } .dim { color: var(--dim); font-size: 14px; }
            table { border-collapse: collapse; } td, th { border: 1px solid var(--line); padding: 2px 8px; text-align: right; }
            img { max-width: 100%; border: 1px solid var(--line); }
            @media print { nav { display: none; } main { margin: 0; } }
            </style></head><body>
            <nav><h2>\(esc(summary))</h2><p class="dim">Host: \(esc(host)).</p><ul>
            \(nav)
            </ul></nav>
            <main>
            \(sections)
            </main>
            <script>
            document.querySelectorAll('[data-jump]').forEach(function (a) {
              a.addEventListener('click', function () {
                document.getElementById(a.getAttribute('data-jump')).scrollIntoView();
              });
            });
            </script>
            </body></html>
            """
    }

    // section writes one scenario.
    private func section(_ r: ScenarioResult) -> String {
        let ran =
            r.failures.isEmpty
            ? "<p class=\"ok\">Passed in \(String(format: "%.3f", r.seconds)) s.</p>"
            : "<ul>" + r.failures.map { "<li class=\"bad\">\(esc($0.rule)): \(esc($0.detail))</li>" }.joined() + "</ul>"
        let rules = r.skipped.map { "<p class=\"dim\">Skipped: \(esc($0)).</p>" } ?? ran
        let notes = r.notes.map { "<li>\(esc($0))</li>" }.joined()
        let rows = r.frames.map { f in
            "<tr><th>\(esc(f.name))</th><td>\(Int(f.x))</td><td>\(Int(f.y))</td><td>\(Int(f.w))</td><td>\(Int(f.h))</td></tr>"
        }.joined()
        let shot = r.shot.map { "<p><img alt=\"Screen at the end of \(esc(r.name))\" src=\"\(esc($0))\"></p>" } ?? ""
        return """
            <section id="\(esc(r.name))"><h3 class="\(r.passed ? "ok" : "bad")">\(mark(r)) \(esc(r.name))</h3>
            \(rules)
            <ul class="dim">\(notes)</ul>
            <table><tr><th>Frame</th><th>x</th><th>y</th><th>w</th><th>h</th></tr>\(rows)</table>
            \(shot)
            </section>
            """
    }

    // mark is the word a scenario's line starts with.
    private func mark(_ r: ScenarioResult) -> String {
        r.skipped != nil ? "Skip" : r.passed ? "Pass" : "Fail"
    }

    // esc escapes text for HTML.
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
