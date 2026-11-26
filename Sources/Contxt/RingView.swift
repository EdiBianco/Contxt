// Native replacement for the Electron prototype's src/renderer/ring.ts +
// style.css. NSDraggingDestination is a real AppKit drag target — it doesn't
// care which window is key or which app is active, so Finder keeps focus
// during the drag while the ring still gets dragEntered/Updated/perform.
//
// Layout: the center circle is the Drop Zone (stack files, drag the stack out
// into a Finder folder). Destination circles sit on a ring around it. The
// hovered destination's action is spelled out in a pill over the center.

import AppKit
import Combine

private final class RingItemLayer {
    let destination: Destination
    var angle: CGFloat
    let circle = CAShapeLayer()
    let icon = CALayer()
    let badge = CALayer()
    let rim = CAShapeLayer()
    var rimColor: NSColor?
    var isHovered = false
    var restingRadius: CGFloat = 0

    init(destination: Destination, angle: CGFloat, diameter: CGFloat, scale: CGFloat) {
        self.destination = destination
        self.angle = angle

        circle.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        circle.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        circle.path = CGPath(ellipseIn: circle.bounds, transform: nil)
        circle.lineWidth = 1

        let iconSize = diameter * 0.70
        var proposed = CGRect(x: 0, y: 0, width: iconSize * scale, height: iconSize * scale)
        let iconImage = destination.iconImage()
        rimColor = RingView.dominantColor(of: iconImage)
        icon.contents = iconImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        icon.contentsScale = scale
        icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        icon.position = CGPoint(x: diameter / 2, y: diameter / 2)
        icon.shadowOpacity = 0.28
        icon.shadowRadius = 3
        icon.shadowOffset = CGSize(width: 0, height: 1)
        circle.addSublayer(icon)
        rim.fillColor = nil
        rim.lineCap = .round
        circle.addSublayer(rim)

        // Only contacts get a corner badge (their channel); folders, apps and
        // tools stay clean so the user's own icon is what you recognise.
        if case .contact = destination, let info = destination.badge {
            let badgeSize = diameter * 0.27
            badge.contents = RingView.badgeImage(symbol: info.symbol, color: info.color, size: badgeSize, scale: scale)
            badge.contentsScale = scale
            badge.bounds = CGRect(x: 0, y: 0, width: badgeSize, height: badgeSize)
            badge.position = CGPoint(x: diameter * 0.82, y: diameter * 0.82)
            circle.addSublayer(badge)
        }
    }

    /// Call once the circle is in the view's layer tree: if the tree is
    /// geometry-flipped (flipped NSView), flip images back so they are upright.
    func orientImages() {
        if icon.contentsAreFlipped() { icon.isGeometryFlipped = true }
        if badge.superlayer != nil, badge.contentsAreFlipped() { badge.isGeometryFlipped = true }
    }
}

final class RingView: NSView, NSDraggingSource {
    static let ringSize: CGFloat = 900
    private static let dropZoneID = "__dropzone"
    private static let hoverScale: CGFloat = 1.16
    private static let dwellSeconds: TimeInterval = 0.7
    private static let aiDwellSeconds: TimeInterval = 0.45

    private static let baseColor = dynamic(dark: NSColor(white: 0.10, alpha: 0.78), light: NSColor(white: 1.0, alpha: 0.74))
    private static let borderColor = dynamic(dark: NSColor(white: 1, alpha: 0.16), light: NSColor(white: 0, alpha: 0.10))
    private static let hoverColor = NSColor.controlAccentColor.withAlphaComponent(0.88)
    private static let wedgeColor = dynamic(dark: NSColor(white: 1, alpha: 0.06), light: NSColor(white: 1, alpha: 0.30))
    private static let hoverFill = dynamic(dark: NSColor(white: 1, alpha: 0.22), light: NSColor(white: 1, alpha: 0.96))
    private static let neutralRim = dynamic(dark: NSColor(white: 1, alpha: 0.45), light: NSColor(white: 0, alpha: 0.28))
    private static let pillColor = dynamic(dark: NSColor(white: 0.06, alpha: 0.86), light: NSColor(white: 1.0, alpha: 0.92))
    private static let pillTextColor = dynamic(dark: NSColor.white, light: NSColor(white: 0.1, alpha: 1))

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Called after a drop (or a drag-out) to hide the ring.
    var onDismiss: (() -> Void)?

    private var scale: CGFloat { CGFloat(Preferences.shared.orbScale) }
    private var itemDiameter: CGFloat { 104 * scale }
    /// Grows with the item count so neighbouring circles (at hover size) never
    /// overlap, capped so the largest circle still fits inside the window.
    private func itemRadius(count: Int) -> CGFloat {
        let base = 215 * scale
        guard count > 2 else { return base }
        let needed = (itemDiameter * Self.hoverScale + 8) / (2 * sin(.pi / CGFloat(count)))
        let limit = Self.ringSize / 2 - itemDiameter * Self.hoverScale / 2 - 6
        return min(max(base, needed), limit)
    }
    private var dropZoneDiameter: CGFloat { 136 * scale }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private var items: [RingItemLayer] = []
    private var hoveredID: String?
    private var trackingArea: NSTrackingArea?

    private let wedgeLayer = CAShapeLayer()
    /// Real backdrop blur, cut to the wedge shapes with a mask image.
    private let blurView = NSVisualEffectView()
    private var wedgeShape: CGPath?
    private var blurMaskDirty = true
    private let dropZoneLayer = CAShapeLayer()
    private let dropZoneIcon = CALayer()
    private let dropZoneCaption = CATextLayer()
    private let dropZoneCount = CATextLayer()
    private let pillLayer = CALayer()
    private let pillText = CATextLayer()

    private var dropZoneHovered = false
    private var isDraggingFiles = false
    private var isInternalDrag = false
    private var dwellTimer: Timer?
    private var modifierTimer: Timer?
    private var lastAltState = false
    private var countObserver: AnyCancellable?

    private var pressedItem: RingItemLayer?
    private var pressedDropZone = false
    private var pressStart = CGPoint.zero
    private var isReordering = false
    private var previewOrder: [RingItemLayer] = []
    private var previewSlot = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])

        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        blurView.frame = bounds
        addSubview(blurView, positioned: .below, relativeTo: nil)
        blurView.wantsLayer = true
        blurView.layer?.zPosition = -2
        wedgeLayer.zPosition = -1
        wedgeLayer.lineJoin = .round
        for sublayer in [wedgeLayer, dropZoneLayer, pillLayer] { layer?.addSublayer(sublayer) }
        dropZoneLayer.addSublayer(dropZoneIcon)
        dropZoneLayer.addSublayer(dropZoneCaption)
        dropZoneLayer.addSublayer(dropZoneCount)
        pillLayer.addSublayer(pillText)
        pillLayer.zPosition = 100
        pillLayer.opacity = 0

        dropZoneCaption.string = "Drop Zone"
        dropZoneCaption.alignmentMode = .center
        dropZoneCaption.fontSize = 10
        dropZoneCaption.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        dropZoneCount.alignmentMode = .center
        dropZoneCount.fontSize = 10
        dropZoneCount.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        dropZoneCount.foregroundColor = NSColor.white.cgColor
        dropZoneCount.backgroundColor = NSColor.systemRed.cgColor
        dropZoneCount.cornerRadius = 8

        pillText.alignmentMode = .center
        pillText.truncationMode = .end
        pillText.fontSize = 13
        pillText.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        dropZoneIcon.shadowOpacity = 0.25
        dropZoneIcon.shadowRadius = 2
        dropZoneIcon.shadowOffset = CGSize(width: 0, height: 1)

        rebuildAll()
        if dropZoneIcon.contentsAreFlipped() { dropZoneIcon.isGeometryFlipped = true }

        countObserver = DropZoneStore.shared.$urls.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshDropZone() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Building

    /// Rebuilds the center and all circles (destinations or orb size changed).
    func rebuildAll() {
        dwellTimer?.invalidate()
        for item in items { item.circle.removeFromSuperlayer() }
        items = []
        hoveredID = nil
        dropZoneHovered = false

        let destinations = DestinationStore.shared.destinations
        let angles = computeItemAngles(destinations.count)
        let radius = itemRadius(count: destinations.count)
        items = destinations.indices.map { i in
            let item = RingItemLayer(destination: destinations[i], angle: angles[i], diameter: itemDiameter, scale: backingScale)
            item.restingRadius = radius
            layer?.addSublayer(item.circle)
            item.orientImages()
            return item
        }

        wedgeShape = wedgePath(count: destinations.count, radius: radius)
        wedgeLayer.path = wedgeShape
        blurMaskDirty = true

        let side = dropZoneDiameter
        dropZoneLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        dropZoneLayer.path = CGPath(ellipseIn: dropZoneLayer.bounds, transform: nil)
        dropZoneLayer.lineWidth = 1
        dropZoneIcon.bounds = CGRect(x: 0, y: 0, width: side * 0.34, height: side * 0.34)
        dropZoneIcon.position = CGPoint(x: side / 2, y: side * 0.40)
        dropZoneCaption.bounds = CGRect(x: 0, y: 0, width: side - 12, height: 14)
        dropZoneCaption.position = CGPoint(x: side / 2, y: side * 0.72)
        dropZoneCount.bounds = CGRect(x: 0, y: 0, width: 22, height: 16)
        dropZoneCount.position = CGPoint(x: side * 0.84, y: side * 0.16)
        for textLayer in [dropZoneCaption, dropZoneCount, pillText] { textLayer.contentsScale = backingScale }
        dropZoneIcon.contentsScale = backingScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutAll()
        CATransaction.commit()
        refreshDropZone()
        hidePill(animated: false)
    }

    private func layoutAll() {
        wedgeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateBlurMask()
        wedgeLayer.fillColor = resolved(Self.wedgeColor)
        wedgeLayer.strokeColor = nil
        dropZoneLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        pillLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for item in items { applyPose(item) }
        applyDropZonePose()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutAll()
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutAll()
        CATransaction.commit()
        refreshDropZone()
    }

    private func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    // MARK: - Poses

    private func circleCenter(of item: RingItemLayer) -> CGPoint {
        let offset = direction(angleDeg: item.angle, radius: item.restingRadius)
        return CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
    }

    private func applyPose(_ item: RingItemLayer) {
        let s: CGFloat = item.isHovered ? Self.hoverScale : 1.0
        item.circle.position = circleCenter(of: item)
        item.circle.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        item.circle.fillColor = item.isHovered ? resolved(Self.hoverFill) : nil
        item.circle.strokeColor = nil
        updateRim(item)
    }

    private var blurMaskSize = CGSize.zero

    private func updateBlurMask() {
        blurView.frame = bounds
        guard let shape = wedgeShape else {
            blurView.isHidden = true
            return
        }
        blurView.isHidden = false
        guard blurMaskDirty || blurMaskSize != bounds.size, bounds.width > 0 else { return }
        blurMaskDirty = false
        blurMaskSize = bounds.size
        blurView.maskImage = NSImage(size: bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: self.bounds.midX, y: self.bounds.midY)
            context.addPath(shape)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }

    /// Wedge segments behind the circles: one neutral frosted slice per item.
    private func wedgePath(count: Int, radius: CGFloat) -> CGPath? {
        guard count >= 3 else { return nil }
        let path = CGMutablePath()
        let step = 360 / CGFloat(count)
        let gap: CGFloat = 3
        let inner = radius - itemDiameter * 0.62
        let outer = radius + itemDiameter * 0.62
        let samples = max(6, Int(step / 4))
        for k in 0..<count {
            let a0 = CGFloat(k) * step - step / 2 + gap / 2
            let span = step - gap
            for i in 0...samples {
                let point = direction(angleDeg: a0 + span * CGFloat(i) / CGFloat(samples), radius: outer)
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            for i in stride(from: samples, through: 0, by: -1) {
                path.addLine(to: direction(angleDeg: a0 + span * CGFloat(i) / CGFloat(samples), radius: inner))
            }
            path.closeSubpath()
        }
        return path
    }

    /// Thin arc on the outer edge of the item's wedge, tinted from its icon.
    private func updateRim(_ item: RingItemLayer) {
        let d = itemDiameter
        let outer = item.restingRadius + d * 0.58
        let span = min(0.7 * 360 / CGFloat(max(items.count, 1)), 44)
        let origin = direction(angleDeg: item.angle, radius: item.restingRadius)
        let path = CGMutablePath()
        let segments = 10
        for i in 0...segments {
            let q = direction(angleDeg: item.angle - span / 2 + span * CGFloat(i) / CGFloat(segments), radius: outer)
            let point = CGPoint(x: d / 2 + q.x - origin.x, y: d / 2 + q.y - origin.y)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        item.rim.path = path
        item.rim.strokeColor = resolved(item.rimColor ?? Self.neutralRim)
        item.rim.lineWidth = item.isHovered ? 4 : 2.5
    }

    /// Average of the vivid pixels of an icon; nil when it is grayscale.
    static func dominantColor(of image: NSImage) -> NSColor? {
        let n = 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, total: CGFloat = 0
        for y in 0..<n {
            for x in 0..<n {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                let weight = c.saturationComponent * c.saturationComponent * (0.3 + c.brightnessComponent)
                r += c.redComponent * weight; g += c.greenComponent * weight; b += c.blueComponent * weight
                total += weight
            }
        }
        guard total > 1.5 else { return nil }
        let color = NSColor(deviceRed: r / total, green: g / total, blue: b / total, alpha: 1)
        // Keep the rim visible on both light and dark wallpapers.
        return NSColor(
            deviceHue: color.hueComponent,
            saturation: max(color.saturationComponent, 0.45),
            brightness: min(max(color.brightnessComponent, 0.6), 0.92),
            alpha: 1
        )
    }

    private func applyDropZonePose() {
        let s: CGFloat = dropZoneHovered ? 1.1 : 1.0
        dropZoneLayer.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        dropZoneLayer.fillColor = resolved(dropZoneHovered ? Self.hoverFill : Self.baseColor)
        dropZoneLayer.strokeColor = resolved(dropZoneHovered ? Self.hoverColor : Self.borderColor)
        dropZoneLayer.lineWidth = dropZoneHovered ? 2.5 : 1
    }

    /// Animates only the one circle whose state flipped, so moving inside a
    /// circle never restarts its animation.
    private func setHovered(_ item: RingItemLayer, _ hovered: Bool, animated: Bool = true) {
        guard item.isHovered != hovered else { return }
        item.isHovered = hovered
        withSpring(animated) { applyPose(item) }
    }

    private func setDropZoneHovered(_ hovered: Bool) {
        guard dropZoneHovered != hovered else { return }
        dropZoneHovered = hovered
        withSpring(true) { applyDropZonePose() }
    }

    private func withSpring(_ animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            // Spring-ish overshoot, matching the original CSS transition.
            CATransaction.setAnimationDuration(0.32)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }

    // MARK: - Drop Zone appearance

    private func refreshDropZone() {
        let count = DropZoneStore.shared.urls.count
        let tint = NSColor.secondaryLabelColor
        var image: CGImage?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 30, weight: .regular)) {
                var rect = CGRect(origin: .zero, size: symbol.size)
                image = Self.tinted(symbol, color: tint).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
        }
        dropZoneIcon.contents = image
        dropZoneCaption.foregroundColor = resolved(.secondaryLabelColor)
        dropZoneCount.string = "\(count)"
        dropZoneCount.isHidden = count == 0
        applyDropZonePose()
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func badgeImage(symbol: String, color: NSColor, size: CGFloat, scale: CGFloat) -> CGImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            ring.stroke()

            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size * 0.5, weight: .bold)) {
                let white = tinted(glyph, color: .white)
                let g = white.size
                white.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height))
            }
            return true
        }
        var rect = CGRect(x: 0, y: 0, width: size * scale, height: size * scale)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - Pill

    private func refreshPill() {
        guard let id = hoveredID else {
            hidePill(animated: true)
            return
        }
        if id == Self.dropZoneID {
            showPill("Add to Drop Zone", dimCenter: false)
        } else if let item = items.first(where: { $0.destination.id == id }) {
            showPill(item.destination.actionText(altKeyHeld: NSEvent.modifierFlags.contains(.option)), dimCenter: true)
        } else {
            hidePill(animated: true)
        }
    }

    private func showPill(_ text: String, dimCenter: Bool) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let width = min(max(textWidth + 32, 96), 300)
        let height: CGFloat = 30

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        pillLayer.cornerRadius = height / 2
        pillLayer.backgroundColor = resolved(Self.pillColor)
        pillLayer.borderColor = resolved(Self.borderColor)
        pillLayer.borderWidth = 1
        pillText.string = text
        pillText.foregroundColor = resolved(Self.pillTextColor)
        pillText.bounds = CGRect(x: 0, y: 0, width: width - 20, height: 17)
        pillText.position = CGPoint(x: width / 2, y: height / 2)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        pillLayer.opacity = 1
        dropZoneLayer.opacity = dimCenter ? 0.3 : 1
        CATransaction.commit()
    }

    private func hidePill(animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.12)
        } else {
            CATransaction.setDisableActions(true)
        }
        pillLayer.opacity = 0
        dropZoneLayer.opacity = 1
        CATransaction.commit()
    }

    // MARK: - Lifecycle (called by the controller)

    /// Clears hover state; call before the panel is shown again.
    func reset() {
        clearHover(animated: false)
        isDraggingFiles = false
        isInternalDrag = false
        DropZoneStore.shared.prune()
        refreshDropZone()
    }

    func beginTracking() {
        lastAltState = NSEvent.modifierFlags.contains(.option)
        modifierTimer?.invalidate()
        modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            let alt = NSEvent.modifierFlags.contains(.option)
            if alt != self.lastAltState {
                self.lastAltState = alt
                if self.hoveredID != nil { self.refreshPill() }
            }
        }
    }

    func endTracking() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        dwellTimer?.invalidate()
    }

    // MARK: - Hit testing & hover

    private enum Target {
        case item(RingItemLayer)
        case dropZone
    }

    private func target(at point: CGPoint) -> Target? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let zoneRadius = dropZoneDiameter / 2 * (dropZoneHovered ? 1.1 : 1.0)
        if hypot(point.x - center.x, point.y - center.y) <= zoneRadius { return .dropZone }

        for item in items {
            let s = item.isHovered ? Self.hoverScale : 1.0
            let c = circleCenter(of: item)
            if hypot(point.x - c.x, point.y - c.y) <= itemDiameter / 2 * s { return .item(item) }
        }
        return nil
    }

    private func updateHover(at point: CGPoint) {
        let found = target(at: point)
        let newID: String?
        switch found {
        case .item(let item): newID = item.destination.id
        case .dropZone: newID = Self.dropZoneID
        case nil: newID = nil
        }
        guard newID != hoveredID else { return }
        hoveredID = newID
        if ChatListController.shared.isVisible { ChatListController.shared.hide() }

        for item in items { setHovered(item, item.destination.id == newID) }
        setDropZoneHovered(newID == Self.dropZoneID)
        refreshPill()
        restartDwell(for: found)
    }

    private func clearHover(animated: Bool = true) {
        dwellTimer?.invalidate()
        hoveredID = nil
        for item in items { setHovered(item, false, animated: animated) }
        if dropZoneHovered {
            dropZoneHovered = false
            withSpring(animated) { applyDropZonePose() }
        }
        hidePill(animated: animated)
    }

    /// While a file is held over a folder, a short wait opens that folder in
    /// Finder so the file can be dropped into one of its subfolders.
    private func restartDwell(for found: Target?) {
        dwellTimer?.invalidate()
        if isDraggingFiles, case .item(let item)? = found, case .ai(_, _, let tool, let chats) = item.destination, !chats.isEmpty {
            dwellTimer = Timer.scheduledTimer(withTimeInterval: Self.aiDwellSeconds, repeats: false) { [weak self] _ in
                guard let self, let window = self.window else { return }
                let anchor = window.convertToScreen(self.convert(item.circle.frame, to: nil))
                ChatListController.shared.show(tool: tool, chats: chats, beside: anchor)
            }
            return
        }
        guard isDraggingFiles, case .item(let item)? = found, case .folder(_, _, let path, _) = item.destination else { return }

        dwellTimer = Timer.scheduledTimer(withTimeInterval: Self.dwellSeconds, repeats: false) { [weak self] _ in
            contxtLog("dwell: opening \(path) in Finder")
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            self?.onDismiss?()
        }
    }

    // MARK: - Mouse (hover, reorder, Drop Zone drag-out)

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard !isReordering else { return }
        clearHover()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressStart = point
        pressedItem = nil
        pressedDropZone = false
        isReordering = false

        switch target(at: point) {
        case .dropZone: pressedDropZone = true
        case .item(let item): pressedItem = item
        case nil: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressStart.x, point.y - pressStart.y) > 6 else { return }

        if pressedDropZone {
            pressedDropZone = false
            beginDropZoneDrag(with: event)
        } else if let item = pressedItem {
            if !isReordering {
                isReordering = true
                previewOrder = items
                previewSlot = items.firstIndex { $0 === item } ?? 0
                setHovered(item, true)
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            item.circle.position = point
            item.circle.zPosition = 50
            CATransaction.commit()
            previewReorder(item, pointer: point)
        }
    }

    /// The dragged circle claims the slot nearest to the pointer; the other
    /// circles slide around the ring to open that gap.
    private func previewReorder(_ item: RingItemLayer, pointer: CGPoint) {
        let count = items.count
        guard count > 1 else { return }

        let step = 360 / CGFloat(count)
        let angle = angleFromCenter(pointer, center: CGPoint(x: bounds.midX, y: bounds.midY))
        let slot = Int((angle / step).rounded()) % count
        guard slot != previewSlot else { return }
        previewSlot = slot

        var order = items.filter { $0 !== item }
        order.insert(item, at: min(slot, order.count))
        previewOrder = order

        for (index, other) in order.enumerated() where other !== item {
            other.angle = CGFloat(index) * step
            withSpring(true) { applyPose(other) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedItem = nil
            pressedDropZone = false
            isReordering = false
        }
        guard isReordering, let item = pressedItem else { return }

        item.circle.zPosition = 0
        let order = previewOrder.map { $0.destination.id }
        if order == items.map({ $0.destination.id }) {
            setHovered(item, false)
            withSpring(true) { applyPose(item) }
        } else {
            DestinationStore.shared.reorder(order) // triggers rebuildAll
        }
    }

    private func beginDropZoneDrag(with event: NSEvent) {
        let urls = DropZoneStore.shared.urls
        guard !urls.isEmpty else { return }

        isInternalDrag = true
        clearHover(animated: false)

        let location = convert(event.locationInWindow, from: nil)
        let draggingItems = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 5)) * 5
            item.setDraggingFrame(NSRect(x: location.x - 24 + offset, y: location.y - 24 + offset, width: 48, height: 48), contents: icon)
            return item
        }

        // The ring must not intercept the drop: make it invisible and click-through while dragging out.
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        contxtLog("drop zone drag ended operation=\(operation.rawValue)")
        isInternalDrag = false
        if !operation.isEmpty { DropZoneStore.shared.clear() }
        window?.alphaValue = 1
        window?.ignoresMouseEvents = false
        onDismiss?()
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isInternalDrag else { return [] }
        isDraggingFiles = true
        updateHover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isInternalDrag else { return [] }
        updateHover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDraggingFiles = false
        clearHover()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDraggingFiles = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDraggingFiles = false
        dwellTimer?.invalidate()

        let point = convert(sender.draggingLocation, from: nil)
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        let found = target(at: point)
        let hoveredItem = items.first { $0.destination.id == hoveredID }
        contxtLog("performDragOperation at \(point) hovered=\(hoveredID ?? "nil") urls=\(urls.count)")

        guard !urls.isEmpty else {
            onDismiss?()
            return false
        }

        let altKeyHeld = NSEvent.modifierFlags.contains(.option)
        var pulsed: CALayer?
        switch found {
        case .dropZone:
            DropZoneStore.shared.add(urls)
            pulsed = dropZoneLayer
        case .item(let item):
            perform(on: item.destination, urls: urls, altKeyHeld: altKeyHeld)
            pulsed = item.circle
        case nil:
            if hoveredID == Self.dropZoneID {
                DropZoneStore.shared.add(urls)
                pulsed = dropZoneLayer
            } else if let hoveredItem {
                perform(on: hoveredItem.destination, urls: urls, altKeyHeld: altKeyHeld)
                pulsed = hoveredItem.circle
            } else {
                onDismiss?()
                return false
            }
        }

        // Confirm the drop with a quick in-place pulse before the ring goes away.
        if let pulsed {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [Self.hoverScale, 0.88, 1.04]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.duration = 0.22
            pulsed.add(pulse, forKey: "drop-pulse")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in self?.onDismiss?() }
        return true
    }

    private func perform(on destination: Destination, urls: [URL], altKeyHeld: Bool) {
        let paths = urls.map(\.path)
        switch destination {
        case .folder(_, _, let path, let mode):
            DropActions.dropOnFolder(destinationPath: path, filePaths: paths, altKeyHeld: altKeyHeld, mode: mode)
        case .app(_, _, let appPath):
            DropActions.dropOnApp(appPath: appPath, filePaths: paths)
        case .script(_, _, let scriptPath):
            DropActions.dropOnScript(scriptPath: scriptPath, filePaths: paths)
        case .contact(_, _, let target):
            DropActions.dropOnContact(target, filePaths: paths)
        case .action(_, _, let action):
            DropActions.dropOnAction(action, filePaths: paths)
        case .shortcut(_, _, let name):
            DropActions.dropOnShortcut(name: name, filePaths: paths)
        case .ai(_, _, let tool, _):
            DropActions.dropOnAI(tool, chat: nil, filePaths: paths)
        }
    }
}
