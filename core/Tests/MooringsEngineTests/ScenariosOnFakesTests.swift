import Foundation

import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// ScenarioRig is one Engine on fakes over one 3440x1440 ultrawide with nothing saved and the features
// given, and the FakeHost that opens and moves its windows.
final class ScenarioRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // clock is the fake clock the host's waits advance.
    let clock = FakeClock(100)
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // store holds the choices the scenarios save.
    let store = FakeStore()
    // engine is the engine under test.
    let engine: Engine
    // host opens, places and closes the fake windows.
    let host: FakeHost

    // init builds the rig with features, every one unless a test names fewer.
    init(features: Engine.Features = .all) {
        engine = newTestEngine(
            newTestPlatform(windows: windows, screens: screens, clock: clock, store: store), features: features)
        host = FakeHost(windows: windows, clock: clock, screens: screens)
        host.store = store
        host.drag = engine.drag
    }
}

// Test 0: Every scenario passes on the fakes, and the report counts them all.
@Test func testScenariosOnFakes() {
    let rig = ScenarioRig()
    let results = Scenarios.run(rig.engine, host: rig.host)
    let report = ScenarioReport(host: "fakes", results: results)
    for r in results {
        print("scenario \(r.name): \(r.notes.joined(separator: "; "))")
    }
    #expect(report.summary == "scenarios: 19 run, 0 failed")
    #expect(report.failures.isEmpty, "\(report.failures)")
    #expect(Set(results.map(\.name)) == Set(Scenarios.all.map(\.name)))
}

// Test 1: Negative control: the strip expected two points wider, the least the 1 point rule cannot
// absorb, fails the pin scenario with its rule, and one point wider does not.
@Test func testScenariosSkewFails() {
    let rig = ScenarioRig()
    #expect(Scenarios.run(rig.engine, host: rig.host, only: ["pinPlacesOnStrip"], skew: 1).first?.passed == true)
    let results = Scenarios.run(rig.engine, host: rig.host, only: ["pinPlacesOnStrip"], skew: 2)
    #expect(results.map(\.name) == ["pinPlacesOnStrip"])
    #expect(
        results.first?.failures.map(\.rule) == ["a pinned window reads back at its strip within 2 s, 1 point"])
}

// Test 6: An engine with no routed features skips the stash, organize, badge and workspace scenarios by
// name with their reasons and runs the rest.
@Test func testScenariosSkipMissingFeature() {
    let rig = ScenarioRig(features: [])
    let results = Scenarios.run(rig.engine, host: rig.host)
    let skipped = results.filter { $0.skipped != nil }
    #expect(skipped.map(\.name) == ["quitRestoresStash", "organize", "channelCycle", "badgeCounts", "workspaceRecall"])
    #expect(
        skipped.map(\.skipped) == [
            "needs stash", "needs organize", "needs organize", "needs badge", "needs workspaces",
        ])
    #expect(ScenarioReport(host: "fakes", results: results).summary == "scenarios: 14 run, 5 skipped, 0 failed")
}

// Test 2: The run puts back the engine's choices and stops its passes.
@Test func testScenariosPutBackChoices() {
    let rig = ScenarioRig()
    rig.engine.anchors.choices.gapPx = 7
    _ = Scenarios.run(rig.engine, host: rig.host, only: ["pausedMovesNothing"])
    #expect(rig.engine.anchors.choices.gapPx == 7)
    #expect(rig.engine.passes.due == nil)
}

// Test 3: A name no scenario has is reported, and run skips it.
@Test func testScenariosUnknownName() {
    #expect(Scenarios.unknown(["pinPlacesOnStrip", "noSuchScenario"]) == ["noSuchScenario"])
    let rig = ScenarioRig()
    #expect(Scenarios.run(rig.engine, host: rig.host, only: ["noSuchScenario"]).isEmpty)
}

// Test 4: The report writes its summary, a failure's rule in the page, and JSON that reads back the same.
@Test func testScenarioReport() throws {
    let failed = ScenarioResult(
        name: "pinPlacesOnStrip",
        failures: [ScenarioFailure(scenario: "pinPlacesOnStrip", rule: "a <rule>", detail: "x & y")],
        frames: [NamedFrame("strip", Frame(x: 0, y: 25, w: 1376, h: 1415))], notes: ["n"], shot: "a.png", seconds: 1)
    let report = ScenarioReport(host: "fakes", results: [failed])
    #expect(report.summary == "scenarios: 1 run, 1 failed")
    #expect(report.html().contains("a &lt;rule&gt;: x &amp; y"))
    #expect(report.html().contains("src=\"a.png\""))
    #expect(report.html().contains("<rect data-name=\"strip\" x=\"0\" y=\"25\" width=\"1376\" height=\"1415\">"))
    let back = try JSONDecoder().decode(ScenarioReport.self, from: report.json())
    #expect(back == report)
}

// Test 5: The PNG checksums match their published check values and a 2x1 picture has the right bytes.
@Test func testPNG() {
    #expect(PNG.crc32(Array("IEND".utf8)) == 0xAE42_6082)
    #expect(PNG.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
    let data = PNG.encode(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 0, 255, 255], red: 0, blue: 2)
    let bytes = [UInt8](data)
    #expect(Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    #expect(Array(bytes.suffix(12)) == [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    #expect(bytes.count == 8 + 25 + (12 + 2 + 5 + 7 + 4) + 12)
}

// Test 7: An app's launch window still open when the rest scenario starts is waited out, so its busy
// passes do not read as passes at rest.
@Test func testScenariosRestWaitsOutLaunch() {
    let rig = ScenarioRig()
    rig.engine.passes.launching = rig.clock.now + Pace.launchSeconds
    let result = Scenarios.run(rig.engine, host: rig.host, only: ["eventsWakeAndRestHolds"]).first
    #expect(result?.passed == true, "\(result?.failures ?? [])")
    #expect(result?.notes.contains { $0.hasPrefix("waited ") } == true)
}
