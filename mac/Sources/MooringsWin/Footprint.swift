import Foundation
import WinSDK

import MooringsCore

// WinFootprint is the layered window that shows where a dragged window will land. Clicks pass
// through it, it never takes the foreground, and it stays out of the taskbar and Alt-Tab.
final class WinFootprint {
    // className is the footprint window's class.
    static let className = "MooringsFootprint"
    // topmost, toolWindow, layered, transparent and noActivate are the WS_EX_ bits of those names.
    static let topmost: DWORD = 0x0000_0008, toolWindow: DWORD = 0x0000_0080, layered: DWORD = 0x0008_0000,
               transparent: DWORD = 0x0000_0020, noActivate: DWORD = 0x0800_0000
    // passThrough is the bits that keep clicks and the foreground away from the footprint.
    static let passThrough = transparent | noActivate
    // exStyle keeps the footprint above every window, out of the taskbar and Alt-Tab, drawn with
    // per-pixel alpha, and passing clicks through.
    static let exStyle = topmost | toolWindow | layered | passThrough
    // fadeTimer is the id of the fade's window timer.
    static let fadeTimer = UINT_PTR(1)
    // fadeSteps is how many alpha steps a fade takes.
    static let fadeSteps = 8

    // activates leaves out the pass-through bits, so a click lands on the footprint and activates
    // it. Only the footprint probe's negative control sets it.
    var activates = false
    // window is the footprint window, nil before the first show.
    private(set) var window: HWND?
    // shown is the frame the footprint shows, nil while hidden.
    private(set) var shown: Frame?
    // last is the frame the footprint last showed, kept after it hides.
    private(set) var last: Frame?
    // shows counts the frames the footprint was drawn at.
    private(set) var shows = 0
    // alpha is the window's constant opacity out of 255, which the fade steps.
    private var alpha = 255
    // fadeTime is the shown style's fade time in seconds, 0 when it does not fade.
    private var fadeTime = 0.0
    // step counts the steps of the fade under way.
    private var step = 0
    // fadingIn is true while the fade under way brings the footprint in, false while it takes it out.
    private var fadingIn = true

    // current is the footprint, which the window procedure reaches since it cannot capture.
    nonisolated(unsafe) static var current: WinFootprint?

    // show draws the footprint at frame in pixels, in style's colors on palette, fading it in when it
    // was hidden and the style fades.
    func show(_ frame: Frame, style: FootprintStyle, palette: Palette = .harbor) {
        guard let hwnd = window ?? create() else { return }
        let fresh = shown == nil
        shown = frame
        last = frame
        shows += 1
        fadeTime = style.fadeTime
        if fresh {
            alpha = fadeTime > 0 ? 0 : 255
        }
        paint(hwnd, frame, style.tints(palette), border: style.borderWidth)
        guard fresh else { return }
        _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        if fadeTime > 0 {
            fade(in: true)
        }
    }

    // hide takes the footprint away, fading it out when the shown style fades.
    func hide() {
        guard let hwnd = window, shown != nil else { return }
        shown = nil
        if fadeTime > 0 {
            fade(in: false)
        } else {
            _ = KillTimer(hwnd, Self.fadeTimer)
            _ = ShowWindow(hwnd, SW_HIDE)
        }
    }

    // create makes the hidden footprint window.
    private func create() -> HWND? {
        let instance = GetModuleHandleW(nil)
        Self.register(instance)
        WinFootprint.current = self
        let ex = activates ? Self.exStyle & ~Self.passThrough : Self.exStyle
        window = CreateWindowExW(ex, wide(Self.className), wide("Moorings footprint"), BannerWindow.popup,
                                 0, 0, 1, 1, nil, nil, instance, nil)
        return window
    }

    // fade starts a fade in or out over the shown style's fade time.
    private func fade(in fadeIn: Bool) {
        guard let hwnd = window else { return }
        fadingIn = fadeIn
        step = 0
        let every = fadeTime / Double(Self.fadeSteps) * 1000
        _ = SetTimer(hwnd, Self.fadeTimer, UINT(max(1, every.rounded())), nil)
    }

    // tick takes one fade step and ends the fade on the last, hiding the window after a fade out.
    private func tick(_ hwnd: HWND) {
        step = min(step + 1, Self.fadeSteps)
        let shown = fadingIn ? step : Self.fadeSteps - step
        alpha = 255 * shown / Self.fadeSteps
        var blend = Self.blend(alpha)
        _ = UpdateLayeredWindow(hwnd, nil, nil, nil, nil, nil, 0, &blend, Self.alphaUpdate)
        guard step == Self.fadeSteps else { return }
        _ = KillTimer(hwnd, Self.fadeTimer)
        if !fadingIn {
            _ = ShowWindow(hwnd, SW_HIDE)
        }
    }

    // alphaUpdate is ULW_ALPHA.
    static let alphaUpdate: DWORD = 0x0000_0002

    // blend returns the per-pixel alpha blend at constant opacity alpha out of 255.
    static func blend(_ alpha: Int) -> BLENDFUNCTION {
        // BlendOp 0 is AC_SRC_OVER and AlphaFormat 1 is AC_SRC_ALPHA.
        BLENDFUNCTION(BlendOp: 0, BlendFlags: 0, SourceConstantAlpha: BYTE(min(max(alpha, 0), 255)),
                      AlphaFormat: 1)
    }

    // pixel returns t as a premultiplied BGRA pixel.
    static func pixel(_ t: Tint) -> UInt32 {
        let a = min(max(t.alpha, 0), 1)
        let byte = { (v: Double) in UInt32((min(max(v, 0), 1) * a * 255).rounded()) }
        return UInt32((a * 255).rounded()) << 24 | byte(t.color.red) << 16 | byte(t.color.green) << 8
            | byte(t.color.blue)
    }

    // paint fills a premultiplied bitmap the size of f with the fill tint inside a border of the stroke
    // tint, border points wide at the window's DPI, and puts it on the window at f.
    private func paint(_ hwnd: HWND, _ f: Frame, _ tints: (fill: Tint, stroke: Tint), border: Double) {
        let w = Int(f.w.rounded()), h = Int(f.h.rounded())
        guard w > 0, h > 0, let screen = GetDC(nil) else { return }
        defer { _ = ReleaseDC(nil, screen) }
        guard let dc = CreateCompatibleDC(screen) else { return }
        defer { _ = DeleteDC(dc) }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(w)
        info.bmiHeader.biHeight = -LONG(h)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let dib = CreateDIBSection(dc, &info, UINT(DIB_RGB_COLORS), &raw, nil, 0), let bits = raw else { return }
        defer { _ = DeleteObject(HGDIOBJ(dib)) }
        let old = SelectObject(dc, HGDIOBJ(dib))
        defer { _ = SelectObject(dc, old) }
        let dpi = GetDpiForWindow(hwnd)
        let scale = dpi > 0 ? Double(dpi) / 96 : 1
        let b = min(Int((max(0, border) * scale).rounded()), min(w, h) / 2)
        Self.draw(bits.bindMemory(to: UInt32.self, capacity: w * h), w: w, h: h, border: b,
                  fill: Self.pixel(tints.fill), stroke: Self.pixel(tints.stroke))
        var size = SIZE(cx: LONG(w), cy: LONG(h))
        var src = POINT(x: 0, y: 0)
        var dst = POINT(x: LONG(f.x.rounded()), y: LONG(f.y.rounded()))
        var blend = Self.blend(alpha)
        _ = UpdateLayeredWindow(hwnd, screen, &dst, &size, dc, &src, 0, &blend, Self.alphaUpdate)
    }

    // draw fills the w by h pixels at px with fill inside a border pixels wide of stroke.
    static func draw(_ px: UnsafeMutablePointer<UInt32>, w: Int, h: Int, border: Int, fill: UInt32,
                     stroke: UInt32) {
        for y in 0..<h {
            let row = px + y * w
            let edgeRow = y < border || y >= h - border
            for x in 0..<w {
                let edge = edgeRow || x < border || x >= w - border
                row[x] = edge ? stroke : fill
            }
        }
    }

    // registered reports whether the window class is registered.
    nonisolated(unsafe) static var registered = false

    // register registers the footprint's window class once.
    private static func register(_ instance: HINSTANCE?) {
        guard !registered else { return }
        registered = true
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.hInstance = instance
        wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
            if let hwnd, let footprint = WinFootprint.current, footprint.window == hwnd {
                switch msg {
                case UINT(WM_MOUSEACTIVATE) where !footprint.activates:
                    return LRESULT(MA_NOACTIVATE)
                case UINT(WM_TIMER) where wParam == WinFootprint.fadeTimer:
                    footprint.tick(hwnd)
                    return 0
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
