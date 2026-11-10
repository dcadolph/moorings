import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// WinBadge is the Windows BadgeView: a small rounded window with the stack's count at the top-right
// corner of the stack's front window. Clicks pass through it, it never takes the foreground, and it
// stays out of the taskbar and Alt-Tab.
final class WinBadge: BadgeView {
    // className is the badge window's class.
    static let className = "MooringsBadge"
    // width and height are the badge's size in points, and margin its inset from the window's corner.
    static let width = 30.0, height = 22.0, margin = 8.0

    // window is the badge window, nil before the first show.
    private(set) var window: HWND?
    // shown is the mark the badge paints, nil when hidden.
    private(set) var shown: BadgeMark?
    // count is the number painted.
    private var count = 0
    // palette is the palette the badge paints in.
    private var palette = Palette.harbor
    // scale is the DPI over 96 of the monitor the badge sits on.
    private var scale = 1.0

    // current is the badge, which the window procedure reaches since it cannot capture.
    nonisolated(unsafe) static var current: WinBadge?

    // show paints count at the top-right corner of front, in pixels; a second show moves it. The badge
    // moves onto front's corner first, so the DPI it reads is that monitor's.
    func show(_ count: Int, at front: Frame, palette: Palette) {
        guard let hwnd = window ?? create() else { return }
        self.count = count
        self.palette = palette
        let right = Int32((front.x + front.w).rounded()), top = Int32(front.y.rounded())
        let flags = UINT(SWP_NOZORDER | SWP_NOACTIVATE)
        _ = SetWindowPos(hwnd, nil, right - 1, top, 1, 1, flags)
        let dpi = GetDpiForWindow(hwnd)
        scale = dpi > 0 ? Double(dpi) / 96 : 1
        let px = { (points: Double) in Int32((points * self.scale).rounded()) }
        let w = px(Self.width), h = px(Self.height), m = px(Self.margin)
        _ = SetWindowPos(hwnd, nil, right - w - m, top + m, w, h, flags)
        _ = SetWindowRgn(hwnd, CreateRoundRectRgn(0, 0, w + 1, h + 1, h, h), true)
        _ = InvalidateRect(hwnd, nil, true)
        _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        shown = BadgeMark(count: count, front: front)
    }

    // hide takes the badge off screen.
    func hide() {
        shown = nil
        guard let window else { return }
        _ = ShowWindow(window, SW_HIDE)
    }

    // create makes the hidden badge window, opaque through the layered alpha, with the footprint's
    // pass-through bits so a click falls through to the window under it.
    private func create() -> HWND? {
        let instance = GetModuleHandleW(nil)
        Self.register(instance)
        WinBadge.current = self
        window = CreateWindowExW(
            WinFootprint.exStyle, wide(Self.className), wide("Moorings badge"), BannerWindow.popup,
            0, 0, 1, 1, nil, nil, instance, nil)
        if let window {
            _ = SetLayeredWindowAttributes(window, 0, 255, BannerWindow.layeredAlpha)
        }
        return window
    }

    // paint fills the badge with the accent and draws the count centered in the label color.
    private func paint(_ hwnd: HWND) {
        var ps = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &ps) else { return }
        defer { _ = EndPaint(hwnd, &ps) }
        var r = RECT()
        _ = GetClientRect(hwnd, &r)
        let fill = CreateSolidBrush(BannerWindow.colorRef(palette.accent))
        _ = FillRect(dc, &r, fill)
        _ = DeleteObject(HGDIOBJ(fill))
        _ = SetBkMode(dc, TRANSPARENT)
        _ = SetTextColor(dc, BannerWindow.colorRef(palette.onAccent))
        let font = CreateFontW(
            -Int32((12 * scale).rounded()), 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DWORD(DEFAULT_CHARSET), 0, 0,
            DWORD(CLEARTYPE_QUALITY), 0, wide("Segoe UI"))
        defer { _ = DeleteObject(HGDIOBJ(font)) }
        let old = SelectObject(dc, HGDIOBJ(font))
        var text = wide("\(count)")
        _ = DrawTextW(dc, &text, -1, &r, UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
        _ = SelectObject(dc, old)
    }

    // registered reports whether the window class is registered.
    nonisolated(unsafe) static var registered = false

    // register registers the badge's window class once.
    private static func register(_ instance: HINSTANCE?) {
        guard !registered else { return }
        registered = true
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.hInstance = instance
        wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
            if let hwnd, let badge = WinBadge.current, badge.window == hwnd {
                switch msg {
                case UINT(WM_PAINT):
                    badge.paint(hwnd)
                    return 0
                case UINT(WM_MOUSEACTIVATE):
                    return LRESULT(MA_NOACTIVATE)
                default:
                    break
                }
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
        let name = wide(className)
        name.withUnsafeBufferPointer { buffer in
            wc.lpszClassName = buffer.baseAddress
            _ = RegisterClassExW(&wc)
        }
    }
}
