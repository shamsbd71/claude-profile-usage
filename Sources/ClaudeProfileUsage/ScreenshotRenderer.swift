import AppKit
import SwiftUI
import UsageCore
import UsageWidgetViews
import WidgetKit

/// `CPU_RENDER=<dir>` renders README screenshots from demo data, then quits.
@MainActor
enum ScreenshotRenderer {
    static func renderAll(to dir: URL, store: UsageStore) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let panel = PanelView(store: store).background(Color(nsColor: .windowBackgroundColor))
        write(panel, appearance: .aqua, to: dir.appendingPathComponent("panel-light.png"))
        write(panel, appearance: .darkAqua, to: dir.appendingPathComponent("panel-dark.png"))

        let snapshot = WidgetSnapshot(accounts: store.accounts, updatedAt: store.now)
        let sizes: [(WidgetFamily, CGSize, String)] = [
            (.systemSmall, CGSize(width: 170, height: 170), "widget-small"),
            (.systemMedium, CGSize(width: 364, height: 170), "widget-medium"),
            (.systemLarge, CGSize(width: 364, height: 382), "widget-large"),
        ]
        for (family, size, name) in sizes {
            let widget = WidgetContentView(snapshot: snapshot, family: family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .clipped()
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(12)
            write(widget, appearance: .aqua, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// `CPU_RENDER_ICON=<file.png>` renders the 1024×1024 app icon (see scripts/make-icon.sh).
    /// Original artwork drawn from shapes: a three-segment usage arc with a needle.
    @discardableResult
    static func renderIcon(to url: URL) -> Bool {
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.32, blue: 0.62),
                                              Color(red: 0.09, green: 0.15, blue: 0.33)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            IconGauge().frame(width: 600, height: 600).offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    private static func write<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Usage gauge for the app icon: green → amber → red arc segments and a white needle.
private struct IconGauge: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * 0.42
            let segments: [(Double, Double, Color)] = [
                (150, 235, Color(red: 0.36, green: 0.85, blue: 0.55)),
                (241, 315, Color(red: 1.00, green: 0.76, blue: 0.28)),
                (321, 390, Color(red: 1.00, green: 0.38, blue: 0.36)),
            ]
            ZStack {
                ForEach(0..<segments.count, id: \.self) { i in
                    Path { p in
                        p.addArc(center: center, radius: radius, startAngle: .degrees(segments[i].0),
                                 endAngle: .degrees(segments[i].1), clockwise: false)
                    }
                    .stroke(segments[i].2, style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round))
                }
                Path { p in
                    let angle = Angle.degrees(300).radians
                    p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.78, y: center.y + sin(angle) * radius * 0.78))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round))
                Circle().fill(.white).frame(width: side * 0.16, height: side * 0.16).position(center)
            }
        }
    }
}
