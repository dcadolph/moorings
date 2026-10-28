// LogCategory is the part of the engine a log line comes from. The Mac maps each to its os.Logger;
// Windows prefixes stderr with it.
public enum LogCategory: String, CaseIterable, Sendable {
    case anchors, actions, overlay, organize, tiling, passes, choices
}
