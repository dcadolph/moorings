import Foundation
import WinSDK

import MooringsCore

// BannerWindow shows what Moorings did in a box at the top center of the ultrawide, in place of a
// system notification, and fades it away. It never takes the foreground.
final class BannerWindow {
    // seconds is how long a banner stays up before it fades.
    static let seconds = 3.0
    // fadeSeconds is how long a banner takes to fade away.
    static let fadeSeconds = 0.4
    // fadeSteps is how many alpha steps the fade takes.
    static let fadeSteps = 8
    // alpha is the banner's opacity before it fades, out of 255.
    static let alpha = 240
    // className is the banner window's class.
    static let className = "MooringsBanner"
    // holdTimer and fadeTimer are the ids of the banner's two window timers.
    static let holdTimer = UINT_PTR(1), fadeTimer = UINT_PTR(2)
    // popup is WS_POPUP, whose high bit does not fit the Int32 Swift imports it as.
    static let popup: DWORD = 0x8000_0000
    // exStyle is WS_EX_TOPMOST, WS_EX_TOOLWINDOW, WS_EX_LAYERED and WS_EX_NOACTIVATE: above every
    // window, out of the taskbar and Alt-Tab, faded by alpha, and never activated by a click.
    static let exStyle: DWORD = 0x0000_0008 | 0x0000_0080 | 0x0008_0000 | 0x0800_0000
    // layeredAlpha is LWA_ALPHA.
    static let layeredAlpha: DWORD = 0x0000_0002

    // minAspect is the ratio a monitor needs to count as ultrawide. Only probes change it.
    let minAspect: Double
    // window is the banner on screen, nil when none.
    private(set) var window: HWND?
    // title is the shown banner's bold first line.
    private var title = ""
    // lines are the shown banner's body lines.
    private var lines: [String] = []
    // scale is the shown banner's monitor scale, 1 at 96 DPI.
    private(set) var scale = 1.0
    // step counts the fade steps taken.
    private var step = 0

    // init builds a banner shown on the ultrawide found with minAspect.
    init(minAspect: Double = Layout.minAspect) {
        self.minAspect = minAspect
    }

    // current is the shown banner, which the window procedure reaches since it cannot capture.
    nonisolated(unsafe) static var current: BannerWindow?

    // show replaces any banner with one titled title saying body. The banner opens without taking
    // the foreground and closes itself after the fade.
    func show(_ title: String, _ body: String) {
        close()
        let screens = Screens.current(minAspect: minAspect)
        guard let screen = screens.wide ?? screens.usable.first else { return }
        self.title = title
        lines = Banner.wrap(body)
        let instance = GetModuleHandleW(nil)
        Self.register(instance)
        BannerWindow.current = self
        var f = Self.frame(lines: lines.count, screen: screen, scale: 1)
        window = CreateWindowExW(Self.exStyle, wide(Self.className), wide("Moorings"), Self.popup,
                                 Int32(f.x), Int32(f.y), Int32(f.w), Int32(f.h), nil, nil, instance,
                                 nil)
        guard let window else { return }
        scale = Double(GetDpiForWindow(window)) / 96
        if scale > 0, scale != 1 {
            f = Self.frame(lines: lines.count, screen: screen, scale: scale)
            _ = SetWindowPos(window, nil, Int32(f.x), Int32(f.y), Int32(f.w), Int32(f.h),
                             UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        } else {
            scale = 1
        }
        _ = SetLayeredWindowAttributes(window, 0, BYTE(Self.alpha), Self.layeredAlpha)
        _ = ShowWindow(window, SW_SHOWNOACTIVATE)
        _ = UpdateWindow(window)
        _ = SetTimer(window, Self.holdTimer, UINT(Self.seconds * 1000), nil)
    }

    // close removes the banner at once.
    func close() {
        guard let window else { return }
        self.window = nil
        _ = DestroyWindow(window)
        if BannerWindow.current === self {
            BannerWindow.current = nil
        }
    }

    // frame returns the banner's box in pixels: the core's banner size at scale, the monitor's
    // DPI over 96, centered across the top of screen.
    static func frame(lines: Int, screen: Frame, scale: Double) -> Frame {
        let points = Banner.frame(lines: lines, screen: screen)
        let w = (points.w * scale).rounded(), h = (points.h * scale).rounded()
        return Frame(x: (screen.x + (screen.w - w) / 2).rounded(),
                     y: screen.y + (Banner.marginY * scale).rounded(), w: w, h: h)
    }

    // registered reports whether the window class is registered.
    nonisolated(unsafe) static var registered = false

    // register registers the banner's window class once.
    private static func register(_ instance: HINSTANCE?) {
        guard !registered else { return }
        registered = true
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.hInstance = instance
        wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
            if let hwnd, let banner = BannerWindow.current, banner.window == hwnd,
               let result = banner.handle(hwnd, msg, wParam, lParam) {
                return result
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
        let name = wide(className)
        name.withUnsafeBufferPointer { buffer in
            wc.lpszClassName = buffer.baseAddress
            _ = RegisterClassExW(&wc)
        }
    }

    // handle answers the banner's messages, nil for the ones the default procedure takes.
    private func handle(_ hwnd: HWND, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch msg {
        case UINT(WM_PAINT):
            paint(hwnd)
            return 0
        case UINT(WM_MOUSEACTIVATE):
            return LRESULT(MA_NOACTIVATE)
        case UINT(WM_TIMER) where wParam == Self.holdTimer:
            _ = KillTimer(hwnd, Self.holdTimer)
            step = 0
            let every = Self.fadeSeconds / Double(Self.fadeSteps) * 1000
            _ = SetTimer(hwnd, Self.fadeTimer, UINT(every.rounded()), nil)
            return 0
        case UINT(WM_TIMER) where wParam == Self.fadeTimer:
            step += 1
            guard step < Self.fadeSteps else {
                _ = KillTimer(hwnd, Self.fadeTimer)
                close()
                return 0
            }
            let left = Self.alpha * (Self.fadeSteps - step) / Self.fadeSteps
            _ = SetLayeredWindowAttributes(hwnd, 0, BYTE(left), Self.layeredAlpha)
            return 0
        default:
            return nil
        }
    }

    // paint draws the banner in the harbor palette: the title in the accent color and the body in
    // the text color on the background.
    private func paint(_ hwnd: HWND) {
        var ps = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &ps) else { return }
        defer { _ = EndPaint(hwnd, &ps) }
        var r = RECT()
        _ = GetClientRect(hwnd, &r)
        let palette = Palette.harbor
        let fill = CreateSolidBrush(Self.colorRef(palette.background))
        _ = FillRect(dc, &r, fill)
        _ = DeleteObject(HGDIOBJ(fill))
        _ = SetBkMode(dc, TRANSPARENT)
        let px = { (points: Double) in Int32((points * self.scale).rounded()) }
        let bold = CreateFontW(-px(14), 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DWORD(DEFAULT_CHARSET), 0, 0,
                               DWORD(CLEARTYPE_QUALITY), 0, wide("Segoe UI"))
        let body = CreateFontW(-px(12), 0, 0, 0, FW_NORMAL, 0, 0, 0, DWORD(DEFAULT_CHARSET), 0, 0,
                               DWORD(CLEARTYPE_QUALITY), 0, wide("Segoe UI"))
        defer {
            _ = DeleteObject(HGDIOBJ(bold))
            _ = DeleteObject(HGDIOBJ(body))
        }
        let old = SelectObject(dc, HGDIOBJ(bold))
        _ = SetTextColor(dc, Self.colorRef(palette.accent))
        _ = TextOutW(dc, px(14), px(10), wide(title), Int32(title.utf16.count))
        _ = SelectObject(dc, HGDIOBJ(body))
        _ = SetTextColor(dc, Self.colorRef(palette.text))
        for (i, line) in lines.enumerated() {
            _ = TextOutW(dc, px(14), px(30 + 16 * Double(i)), wide(line), Int32(line.utf16.count))
        }
        _ = SelectObject(dc, old)
    }

    // colorRef converts c to a GDI COLORREF, red in the low byte.
    static func colorRef(_ c: RGB) -> COLORREF {
        let byte = { (v: Double) in COLORREF((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c.red) | byte(c.green) << 8 | byte(c.blue) << 16
    }
}
