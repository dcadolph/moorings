import MooringsCore
import Testing

// name reads the action from an action link and nothing from any other text.
@Test(
    arguments: [
        ("moorings://action?name=left-half", "left-half"),
        ("MOORINGS://ACTION?name=left-half", "left-half"),
        ("moorings://action/?name=left-half", "left-half"),
        ("moorings://action?other=1&name=left-half", "left-half"),
        ("moorings://action?name=chain:My%20Chain", "chain:My Chain"),
        ("moorings://action", nil),
        ("moorings://action?name=", nil),
        ("moorings://action?other=left-half", nil),
        ("moorings://elsewhere?name=left-half", nil),
        ("https://action?name=left-half", nil),
        ("--probe", nil),
        ("", nil),
    ] as [(String, String?)])
func testActionLinkName(link: String, want: String?) {
    #expect(ActionLink.name(in: link) == want)
}

// isLink takes any moorings link in any case, since main ignores every argument after one.
@Test(
    arguments: [
        ("moorings://action?name=left-half", true),
        ("MoOrInGs://elsewhere", true),
        ("moorings:", false),
        ("--action", false),
        ("", false),
    ] as [(String, Bool)])
func testActionLinkIsLink(text: String, want: Bool) {
    #expect(ActionLink.isLink(text) == want)
}
