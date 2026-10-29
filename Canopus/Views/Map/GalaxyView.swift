// The 3D map of known space (the desktop's GalaxyMap.tsx, drawn with Metal instead of three.js): systems
// coloured by security, faint stargate links, a glow where ships died in the last hour, the route, rings
// on the current and selected systems, region and system names placed over the view. One finger orbits,
// two fingers move, a pinch zooms, a tap picks the nearest system.

import MetalKit
import SwiftUI
import UIKit
import EVEStaticData

/// What the map shows besides the systems; set from SwiftUI, drawn on the next frame.
struct GalaxyOverlay: Equatable {
    var showGates = true
    var showKills = true
    /// Ship + pod kills in the last hour by system id.
    var kills: [Int: Int] = [:]
    var route: [Int] = []
    var current: Int?
    var selected: Int?
    var avoid: Set<Int> = []
    var noted: Set<Int> = []
    /// Sovereignty on: systems coloured by holder instead of security.
    var sovColors: [Int: SIMD4<Float>]?
    var skyhooks: [Int] = []
    var timers: [Int] = []
    /// The alliance's jump bridges (system id pairs), drawn as arcs.
    var bridges: [GalaxyPair] = []
    /// A capital's jump range: the sphere around the start and the systems inside it.
    var jump: GalaxyJump?
}

struct GalaxyPair: Equatable, Codable, Hashable {
    let a: Int
    let b: Int
}

struct GalaxyJump: Equatable {
    let from: Int
    /// Light years.
    let range: Float
    let systems: [Int]
}

/// Drives the map from SwiftUI: camera moves and the selection callback.
@MainActor
final class GalaxyController {
    fileprivate weak var view: GalaxyMTKView?
    var onSelect: (Int?) -> Void = { _ in }

    /// Centres on a system and comes close.
    func fly(to systemId: Int) { view?.fly(to: systemId) }
    /// Frames a set of systems (a route), keeping the viewing angle.
    func fit(_ systemIds: [Int]) { view?.fit(systemIds) }
    func show(_ mode: GalaxyMTKView.ViewMode) { view?.show(mode) }
}

struct GalaxyMapView: UIViewRepresentable {
    let data: GalaxyData
    let overlay: GalaxyOverlay
    let controller: GalaxyController

    func makeUIView(context: Context) -> GalaxyMTKView {
        let v = GalaxyMTKView(data: data)
        controller.view = v
        v.onSelect = { [weak controller] i in controller?.onSelect(i) }
        v.overlay = overlay
        return v
    }

    func updateUIView(_ v: GalaxyMTKView, context: Context) {
        controller.view = v
        if v.overlay != overlay { v.overlay = overlay }
    }
}

// MARK: - The view

final class GalaxyMTKView: MTKView, MTKViewDelegate {
    enum ViewMode { case top, side, all }

    /// How many system names to show when zoomed in, nearest to the centre of the view first.
    private static let systemLabelCount = 40
    /// Camera distance (ly) below which system names appear.
    private static let systemLabelDistance: Float = 28
    private static let pickRadius: CGFloat = 22

    let data: GalaxyData
    var onSelect: (Int?) -> Void = { _ in }
    var overlay = GalaxyOverlay() { didSet { rebuildOverlay(old: oldValue) } }

    private let queue: MTLCommandQueue
    private var dotPipeline: MTLRenderPipelineState!
    private var ringPipeline: MTLRenderPipelineState!
    private var glowPipeline: MTLRenderPipelineState!
    private var linePipeline: MTLRenderPipelineState!

    private var starBuffer: MTLBuffer!
    private var starColors: MTLBuffer!
    private var gateEnds: MTLBuffer?
    private var gateColors: MTLBuffer?
    private var gateCount = 0
    private var killPoints: (MTLBuffer, MTLBuffer, Int)?
    private var routeLine: (MTLBuffer, MTLBuffer, Int)?
    private var routeDots: (MTLBuffer, MTLBuffer, Int)?
    private var rings: (MTLBuffer, MTLBuffer, Int)?
    private var sovMarks: (MTLBuffer, MTLBuffer, Int)?
    private var bridgeLines: (MTLBuffer, MTLBuffer, Int)?
    private var jumpLines: (MTLBuffer, MTLBuffer, Int)?
    private var jumpDots: (MTLBuffer, MTLBuffer, Int)?
    private var secColors: [SIMD4<Float>] = []

    // Camera: orbit around `target`.
    private var target = SIMD3<Float>(0, 0, 0)
    private var distance: Float = 100
    private var yaw: Float = 0
    private var pitch: Float = 0.9
    private var homeTarget = SIMD3<Float>(0, 0, 0)
    private var homeDistance: Float = 100
    private var flight: (from: SIMD3<Float>, to: SIMD3<Float>, d0: Float, d1: Float, p0: Float, p1: Float, start: CFTimeInterval)?

    private var regionLabels: [(label: UILabel, pos: SIMD3<Float>)] = []
    private var systemLabels: [UILabel] = []
    private var noteLabels: [UILabel] = []
    private let labelLayer = UIView()

    init(data: GalaxyData) {
        self.data = data
        let device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        super.init(frame: .zero, device: device)
        delegate = self
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0x13 / 255.0, green: 0x14 / 255.0, blue: 0x16 / 255.0, alpha: 1)
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 60
        isMultipleTouchEnabled = true
        buildPipelines(device)
        buildStatic(device)
        buildLabels()
        addGestures()
        home()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Setup

    private func buildPipelines(_ device: MTLDevice) {
        let library = try! device.makeLibrary(source: GalaxyShaders.source, options: nil)
        func pipeline(_ vs: String, _ fs: String, additive: Bool = false) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vs)
            d.fragmentFunction = library.makeFunction(name: fs)
            let c = d.colorAttachments[0]!
            c.pixelFormat = colorPixelFormat
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        dotPipeline = pipeline("point_vs", "dot_fs")
        ringPipeline = pipeline("point_vs", "ring_fs")
        glowPipeline = pipeline("point_vs", "dot_fs", additive: true)
        linePipeline = pipeline("line_vs", "line_fs")
    }

    private func buildStatic(_ device: MTLDevice) {
        let n = data.count
        var pos = [SIMD4<Float>](), col = [SIMD4<Float>]()
        pos.reserveCapacity(n)
        col.reserveCapacity(n)
        var centre = SIMD3<Float>(0, 0, 0)
        for i in 0..<n {
            pos.append(SIMD4(data.positions[i], 5))
            col.append(GalaxyColors.security(data.security[i]))
            centre += data.positions[i]
        }
        centre /= Float(max(n, 1))
        starBuffer = device.makeBuffer(bytes: pos, length: MemoryLayout<SIMD4<Float>>.stride * max(n, 1))
        starColors = device.makeBuffer(bytes: col, length: MemoryLayout<SIMD4<Float>>.stride * max(n, 1))
        secColors = col

        // Stargates: coloured like their systems, faint so the stars stay readable.
        var ends = [SIMD4<Float>](), ecol = [SIMD4<Float>]()
        for (a, b) in data.edges {
            ends.append(SIMD4(data.positions[a], 0.6))
            ends.append(SIMD4(data.positions[b], 0))
            ecol.append(col[a] * SIMD4(1, 1, 1, 0.28))
            ecol.append(col[b] * SIMD4(1, 1, 1, 0.28))
        }
        gateCount = data.edges.count
        if gateCount > 0 {
            gateEnds = device.makeBuffer(bytes: ends, length: MemoryLayout<SIMD4<Float>>.stride * ends.count)
            gateColors = device.makeBuffer(bytes: ecol, length: MemoryLayout<SIMD4<Float>>.stride * ecol.count)
        }

        let radius = data.positions.reduce(Float(0)) { max($0, simd_length($1 - centre)) }
        homeTarget = centre
        homeDistance = radius * simd_length(SIMD2<Float>(0.95, 0.7))
    }

    private func buildLabels() {
        labelLayer.isUserInteractionEnabled = false
        addSubview(labelLayer)
        // Region labels at the centre of each region's systems; bigger regions first, so when labels
        // would overlap the smaller region's name is hidden.
        var sums = [Int: (SIMD3<Float>, Int)]()
        for i in 0..<data.count {
            let r = data.region[i]
            let s = sums[r] ?? (.zero, 0)
            sums[r] = (s.0 + data.positions[i], s.1 + 1)
        }
        regionLabels = sums.sorted { $0.value.1 > $1.value.1 }.map { r, s in
            let l = makeLabel(font: UIFont(name: "Exo 2", size: 12) ?? .systemFont(ofSize: 12), color: UIColor(C.text2), kern: 1)
            l.text = data.regionNames[r].uppercased()
            l.sizeToFit()
            return (l, s.0 / Float(s.1))
        }
        systemLabels = (0..<Self.systemLabelCount).map { _ in
            makeLabel(font: UIFont(name: "IBM Plex Sans", size: 11) ?? .systemFont(ofSize: 11), color: UIColor(C.muted), kern: 0)
        }
    }

    private func makeLabel(font: UIFont, color: UIColor, kern: CGFloat) -> UILabel {
        let l = UILabel()
        l.font = font
        l.textColor = color
        l.alpha = 0
        l.layer.shadowColor = UIColor(red: 0x13 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1).cgColor
        l.layer.shadowRadius = 3
        l.layer.shadowOpacity = 1
        l.layer.shadowOffset = .zero
        labelLayer.addSubview(l)
        return l
    }

    private var placedHome = false

    override func layoutSubviews() {
        super.layoutSubviews()
        labelLayer.frame = bounds
        if !placedHome, bounds.width > 0 {
            placedHome = true
            home()
        }
        setNeedsDisplay()
    }

    // MARK: Overlay layers

    private func rebuildOverlay(old: GalaxyOverlay) {
        guard let device else { return }
        let o = overlay
        // Kills in the last hour: three sizes (a lone kill, a fight, a big fight), under the stars.
        if o.kills != old.kills || o.showKills != old.showKills || killPoints == nil {
            var pos = [SIMD4<Float>](), col = [SIMD4<Float>]()
            if o.showKills {
                for (id, n) in o.kills where n > 0 {
                    guard let i = data.index[id] else { continue }
                    pos.append(SIMD4(data.positions[i], n >= 10 ? 26 : n >= 3 ? 16 : 10))
                    col.append(SIMD4(1, 0x4A / 255, 0x2E / 255, 0.38))
                }
            }
            killPoints = buffers(device, pos, col)
        }
        // Route: a white line through the systems, accent dots on them.
        if o.route != old.route || routeLine == nil {
            let idx = o.route.compactMap { data.index[$0] }
            var ends = [SIMD4<Float>](), lcol = [SIMD4<Float>]()
            for k in idx.indices.dropLast() {
                ends.append(SIMD4(data.positions[idx[k]], 2))
                ends.append(SIMD4(data.positions[idx[k + 1]], 0))
                lcol.append(SIMD4(1, 1, 1, 0.9))
                lcol.append(SIMD4(1, 1, 1, 0.9))
            }
            routeLine = buffers(device, ends, lcol, count: ends.count / 2)
            let accent = GalaxyColors.rgba(UIColor(C.accent))
            routeDots = buffers(device, idx.map { SIMD4(data.positions[$0], 9) }, idx.map { _ in accent })
        }
        // Sovereignty: stars coloured by holder; raidable Skyhooks and sovereignty timers marked.
        if o.sovColors != old.sovColors || o.skyhooks != old.skyhooks || o.timers != old.timers || sovMarks == nil {
            var col = secColors
            if let sov = o.sovColors {
                let dim = SIMD4<Float>(0x3A / 255, 0x3C / 255, 0x42 / 255, 1), open = SIMD4<Float>(0x9D / 255, 0x9E / 255, 0x99 / 255, 1)
                for i in 0..<data.count {
                    col[i] = sov[data.ids[i]] ?? (data.security[i] >= 0.45 ? dim : open)
                }
            }
            col.withUnsafeBytes { memcpy(starColors.contents(), $0.baseAddress!, $0.count) }
            var pos = [SIMD4<Float>](), mc = [SIMD4<Float>]()
            if o.sovColors != nil {
                for (ids, color, size) in [(o.skyhooks, SIMD4<Float>(0xC7 / 255, 0x7D / 255, 1, 1), Float(13)), (o.timers, SIMD4<Float>(1, 0x9F / 255, 0x1C / 255, 1), 24)] {
                    for id in ids { if let i = data.index[id] { pos.append(SIMD4(data.positions[i], size)); mc.append(color) } }
                }
            }
            sovMarks = buffers(device, pos, mc)
        }
        // Jump bridges: arcs above the plane, in the star colour.
        if o.bridges != old.bridges || bridgeLines == nil {
            var ends = [SIMD4<Float>](), bc = [SIMD4<Float>]()
            let star = GalaxyColors.rgba(UIColor(C.star)) * SIMD4(1, 1, 1, 0.85)
            for pair in o.bridges {
                guard let i = data.index[pair.a], let j = data.index[pair.b] else { continue }
                let a = data.positions[i], b = data.positions[j]
                var mid = (a + b) / 2
                mid.y += simd_length(a - b) * 0.25
                var prev = a
                for k in 1...16 {
                    let t = Float(k) / 16
                    let p = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * mid + t * t * b
                    ends.append(SIMD4(prev, 1)); ends.append(SIMD4(p, 0))
                    bc.append(star); bc.append(star)
                    prev = p
                }
            }
            bridgeLines = buffers(device, ends, bc, count: ends.count / 2)
        }
        // Capital jump range: a faint wire sphere and the systems a jump drive can enter.
        if o.jump != old.jump || (o.jump != nil && jumpLines == nil) {
            jumpLines = nil
            jumpDots = nil
            if let j = o.jump, let i = data.index[j.from] {
                let c = data.positions[i], reach = SIMD4<Float>(0x8E / 255, 0xCB / 255, 1, 1)
                var ends = [SIMD4<Float>](), jc = [SIMD4<Float>]()
                func circle(_ point: (Float) -> SIMD3<Float>) {
                    for k in 0..<48 {
                        ends.append(SIMD4(c + point(Float(k) / 48 * 2 * .pi), 0.6)); ends.append(SIMD4(c + point(Float(k + 1) / 48 * 2 * .pi), 0))
                        jc.append(reach * SIMD4(1, 1, 1, 0.12)); jc.append(reach * SIMD4(1, 1, 1, 0.12))
                    }
                }
                for m in 0..<12 {
                    let phi = Float(m) / 12 * .pi
                    circle { t in j.range * SIMD3(cos(t) * cos(phi), sin(t), cos(t) * sin(phi)) }
                }
                for l in 1..<6 {
                    let lat = Float(l) / 6 * .pi - .pi / 2
                    circle { t in j.range * SIMD3(cos(lat) * cos(t), sin(lat), cos(lat) * sin(t)) }
                }
                jumpLines = buffers(device, ends, jc, count: ends.count / 2)
                let idx = j.systems.compactMap { data.index[$0] }
                jumpDots = buffers(device, idx.map { SIMD4(data.positions[$0], 9) }, idx.map { _ in reach })
            }
        }
        // Rings: avoided systems, the current one, the selection.
        var pos = [SIMD4<Float>](), col = [SIMD4<Float>]()
        func ring(_ id: Int?, _ c: SIMD4<Float>) {
            guard let id, let i = data.index[id] else { return }
            pos.append(SIMD4(data.positions[i], 22))
            col.append(c)
        }
        o.avoid.forEach { ring($0, GalaxyColors.rgba(UIColor(C.muted))) }
        ring(o.current, GalaxyColors.rgba(UIColor(C.accent)))
        ring(o.selected, SIMD4(1, 1, 1, 1))
        rings = buffers(device, pos, col)
        setNeedsDisplay()
    }

    private func buffers(_ device: MTLDevice, _ a: [SIMD4<Float>], _ b: [SIMD4<Float>], count: Int? = nil) -> (MTLBuffer, MTLBuffer, Int)? {
        guard !a.isEmpty,
              let x = device.makeBuffer(bytes: a, length: MemoryLayout<SIMD4<Float>>.stride * a.count),
              let y = device.makeBuffer(bytes: b, length: MemoryLayout<SIMD4<Float>>.stride * b.count) else { return nil }
        return (x, y, count ?? a.count)
    }

    // MARK: Camera

    private var eye: SIMD3<Float> {
        target + distance * SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    private func viewProjection(size: CGSize) -> simd_float4x4 {
        let aspect = Float(size.width / max(size.height, 1))
        return GalaxyMath.perspective(fovY: 50 * .pi / 180, aspect: aspect, near: 0.05, far: 2000)
            * GalaxyMath.lookAt(eye: eye, target: target, up: SIMD3(0, 1, 0))
    }

    /// The whole of New Eden fits a narrow (portrait) view too.
    private var fittedHomeDistance: Float {
        let aspect = Float(bounds.width / max(bounds.height, 1))
        return aspect > 0 && aspect < 1 ? homeDistance * min(1.8, 0.85 / aspect) : homeDistance
    }

    private func home() {
        target = homeTarget
        distance = fittedHomeDistance
        yaw = 0
        pitch = atan2(0.95, 0.7)
    }

    private func animate(to: SIMD3<Float>, distance d1: Float, pitch p1: Float? = nil) {
        flight = (target, to, distance, d1, pitch, p1 ?? pitch, CACurrentMediaTime())
        isPaused = false
    }

    func fly(to systemId: Int) {
        guard let i = data.index[systemId] else { return }
        animate(to: data.positions[i], distance: 14)
        onSelect(systemId)
    }

    func fit(_ systemIds: [Int]) {
        let pts = systemIds.compactMap { data.index[$0] }.map { data.positions[$0] }
        guard !pts.isEmpty else { return }
        let lo = pts.reduce(pts[0]) { simd_min($0, $1) }, hi = pts.reduce(pts[0]) { simd_max($0, $1) }
        let c = (lo + hi) / 2
        animate(to: c, distance: max(4, simd_length(hi - lo) / 2) * 2.6)
    }

    func show(_ mode: ViewMode) {
        switch mode {
        case .all: animate(to: homeTarget, distance: fittedHomeDistance, pitch: atan2(0.95, 0.7))
        case .top: animate(to: target, distance: distance, pitch: .pi / 2 - 0.001)
        case .side: animate(to: target, distance: distance, pitch: 0.05)
        }
    }

    // MARK: Gestures

    private func addGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(onOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        let move = UIPanGestureRecognizer(target: self, action: #selector(onMove(_:)))
        move.minimumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        for g in [orbit, move, pinch, tap] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    @objc private func onOrbit(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        flight = nil
        yaw -= Float(t.x) * 0.006
        pitch = min(.pi / 2 - 0.001, max(-.pi / 2 + 0.001, pitch + Float(t.y) * 0.006))
        setNeedsDisplay()
    }

    @objc private func onMove(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        flight = nil
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let scale = distance * 2 * tan(25 * .pi / 180) / Float(max(bounds.height, 1))
        target += (-right * Float(t.x) + up * Float(t.y)) * scale
        setNeedsDisplay()
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        flight = nil
        distance = min(400, max(1.5, distance / Float(g.scale)))
        g.scale = 1
        setNeedsDisplay()
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        onSelect(pick(g.location(in: self)).map { data.ids[$0] })
    }

    /// The nearest projected system within a finger's reach.
    private func pick(_ p: CGPoint) -> Int? {
        let vp = viewProjection(size: bounds.size)
        var best: Int?
        var bestD = Self.pickRadius * Self.pickRadius
        for i in 0..<data.count {
            guard let s = project(data.positions[i], vp) else { continue }
            let d = (s.x - p.x) * (s.x - p.x) + (s.y - p.y) * (s.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Screen point of a map position, or nil when it is behind the camera or off screen.
    private func project(_ v: SIMD3<Float>, _ vp: simd_float4x4) -> CGPoint? {
        let c = vp * SIMD4(v, 1)
        guard c.w > 0 else { return nil }
        let n = SIMD2(c.x, c.y) / c.w
        guard abs(n.x) <= 1.1, abs(n.y) <= 1.1, c.z / c.w <= 1 else { return nil }
        return CGPoint(x: CGFloat(n.x + 1) / 2 * bounds.width, y: CGFloat(1 - n.y) / 2 * bounds.height)
    }

    // MARK: Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { setNeedsDisplay() }

    func draw(in view: MTKView) {
        if let f = flight {
            let k = min(1, Float((CACurrentMediaTime() - f.start) / 0.7))
            let e = k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2
            target = f.from + (f.to - f.from) * e
            distance = f.d0 + (f.d1 - f.d0) * e
            pitch = f.p0 + (f.p1 - f.p0) * e
            if k >= 1 {
                flight = nil
                isPaused = true
            }
        }
        let vp = viewProjection(size: bounds.size)
        placeLabels(vp)

        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = GalaxyUniforms(viewProj: vp, viewport: SIMD2(Float(drawableSize.width), Float(drawableSize.height)), pointScale: Float(contentScaleFactor))

        func points(_ p: MTLRenderPipelineState, _ b: (MTLBuffer, MTLBuffer, Int)?) {
            guard let b else { return }
            enc.setRenderPipelineState(p)
            enc.setVertexBuffer(b.0, offset: 0, index: 0)
            enc.setVertexBuffer(b.1, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<GalaxyUniforms>.stride, index: 2)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: b.2)
        }
        func lines(_ ends: MTLBuffer?, _ colors: MTLBuffer?, _ count: Int) {
            guard let ends, let colors, count > 0 else { return }
            enc.setRenderPipelineState(linePipeline)
            enc.setVertexBuffer(ends, offset: 0, index: 0)
            enc.setVertexBuffer(colors, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<GalaxyUniforms>.stride, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        }

        points(glowPipeline, killPoints)
        if overlay.showGates { lines(gateEnds, gateColors, gateCount) }
        lines(jumpLines?.0, jumpLines?.1, jumpLines?.2 ?? 0)
        points(dotPipeline, (starBuffer, starColors, data.count))
        lines(bridgeLines?.0, bridgeLines?.1, bridgeLines?.2 ?? 0)
        points(dotPipeline, jumpDots)
        points(dotPipeline, sovMarks)
        lines(routeLine?.0, routeLine?.1, routeLine?.2 ?? 0)
        points(dotPipeline, routeDots)
        points(ringPipeline, rings)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func placeLabels(_ vp: simd_float4x4) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var taken: [CGRect] = []
        // Regions fade out as you zoom in, system names fade in.
        let regionAlpha = CGFloat(min(1, max(0, (distance - 12) / 30)))
        for r in regionLabels {
            guard regionAlpha > 0, let at = project(r.pos, vp) else { r.label.alpha = 0; continue }
            let s = r.label.bounds.size
            let box = CGRect(x: at.x - s.width / 2 - 6, y: at.y - s.height / 2 - 2, width: s.width + 12, height: s.height + 4)
            if taken.contains(where: { $0.intersects(box) }) { r.label.alpha = 0; continue }
            taken.append(box)
            r.label.center = at
            r.label.alpha = regionAlpha
        }
        var near: [(i: Int, d: Float)] = []
        if distance < Self.systemLabelDistance {
            let reach = distance * 0.9
            for i in 0..<data.count {
                let d = simd_length_squared(data.positions[i] - target)
                if d < reach * reach { near.append((i, d)) }
            }
            near.sort { $0.d < $1.d }
        }
        let alpha = CGFloat(min(1, max(0, (Self.systemLabelDistance - distance) / 8)))
        var k = 0
        for label in systemLabels {
            var shown = false
            while !shown && k < near.count {
                let i = near[k].i
                k += 1
                guard let at = project(data.positions[i], vp) else { continue }
                if label.text != data.names[i] {
                    label.text = data.names[i]
                    label.sizeToFit()
                }
                let s = label.bounds.size
                let box = CGRect(x: at.x - s.width / 2, y: at.y + 5, width: s.width, height: s.height)
                if taken.contains(where: { $0.intersects(box) }) { continue }
                taken.append(box)
                label.center = CGPoint(x: at.x, y: at.y + 5 + s.height / 2)
                label.alpha = alpha
                shown = true
            }
            if !shown { label.alpha = 0 }
        }
        // ✎ next to systems with a note.
        let noted = Array(overlay.noted)
        while noteLabels.count < noted.count {
            let l = makeLabel(font: .systemFont(ofSize: 11), color: UIColor(C.warn), kern: 0)
            l.text = "✎"
            l.sizeToFit()
            noteLabels.append(l)
        }
        for (k, l) in noteLabels.enumerated() {
            guard k < noted.count, let i = data.index[noted[k]], let at = project(data.positions[i], vp) else { l.alpha = 0; continue }
            l.center = CGPoint(x: at.x + 10, y: at.y - 10)
            l.alpha = 1
        }
    }
}

extension GalaxyMTKView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch and two-finger move together; a one-finger orbit alone.
        !(g is UITapGestureRecognizer || other is UITapGestureRecognizer)
            && (g as? UIPanGestureRecognizer)?.maximumNumberOfTouches != 1
            && (other as? UIPanGestureRecognizer)?.maximumNumberOfTouches != 1
    }
}

// MARK: - Shaders and maths

private struct GalaxyUniforms {
    var viewProj: simd_float4x4
    var viewport: SIMD2<Float>
    var pointScale: Float
}

private enum GalaxyShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float4x4 viewProj; float2 viewport; float pointScale; };

    struct PointOut {
        float4 position [[position]];
        float4 color;
        float size [[point_size]];
    };

    // buffer 0: xyz + size in points; buffer 1: colour.
    vertex PointOut point_vs(uint vid [[vertex_id]], const device float4* p [[buffer(0)]],
                             const device float4* c [[buffer(1)]], constant Uniforms& u [[buffer(2)]]) {
        PointOut o;
        o.position = u.viewProj * float4(p[vid].xyz, 1);
        o.color = c[vid];
        o.size = p[vid].w * u.pointScale;
        return o;
    }

    // A soft round dot (the desktop's dotTexture: full to 35% of the radius, fading out).
    fragment float4 dot_fs(PointOut in [[stage_in]], float2 pc [[point_coord]]) {
        float d = length(pc - 0.5) * 2;
        float a = d < 0.35 ? mix(1.0, 0.9, d / 0.35) : max(0.0, 0.9 * (1 - (d - 0.35) / 0.65));
        return float4(in.color.rgb, in.color.a * a);
    }

    // A ring around a system (current, selected, avoided).
    fragment float4 ring_fs(PointOut in [[stage_in]], float2 pc [[point_coord]]) {
        float d = length(pc - 0.5) * 2;
        float a = smoothstep(0.62, 0.72, d) * (1 - smoothstep(0.86, 0.96, d));
        return float4(in.color.rgb, in.color.a * a);
    }

    struct LineOut { float4 position [[position]]; float4 color; };

    // Segment `iid` from ends[2*iid] (xyz, width in points) to ends[2*iid+1], drawn as a screen-space quad.
    vertex LineOut line_vs(uint vid [[vertex_id]], uint iid [[instance_id]], const device float4* ends [[buffer(0)]],
                           const device float4* colors [[buffer(1)]], constant Uniforms& u [[buffer(2)]]) {
        const float2 corners[6] = { float2(0, -1), float2(0, 1), float2(1, -1), float2(1, -1), float2(0, 1), float2(1, 1) };
        float2 corner = corners[vid];
        float4 a = u.viewProj * float4(ends[2 * iid].xyz, 1);
        float4 b = u.viewProj * float4(ends[2 * iid + 1].xyz, 1);
        LineOut o;
        o.color = colors[2 * iid + uint(corner.x)];
        if (a.w <= 0.0001 || b.w <= 0.0001) { o.position = float4(0, 0, 2, 1); return o; }
        float2 sa = a.xy / a.w * u.viewport, sb = b.xy / b.w * u.viewport;
        float2 dir = normalize(sb - sa + float2(1e-6, 0));
        float2 normal = float2(-dir.y, dir.x);
        float width = max(1.0, ends[2 * iid].w * u.pointScale);
        float4 p = corner.x < 0.5 ? a : b;
        p.xy += normal * corner.y * width / u.viewport * p.w;
        o.position = p;
        return o;
    }

    fragment float4 line_fs(LineOut in [[stage_in]]) { return in.color; }
    """
}

enum GalaxyMath {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY / 2), x = y / aspect, z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        var s = simd_cross(f, up)
        if simd_length(s) < 1e-5 { s = SIMD3(1, 0, 0) }
        s = simd_normalize(s)
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0), SIMD4(s.y, u.y, -f.y, 0), SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)))
    }
}

enum GalaxyColors {
    /// The desktop's security colours (format.ts SEC_COLORS).
    private static let sec: [UInt32] = [0x8F2F69, 0xB52D2D, 0xBE3A1E, 0xE65C1E, 0xE6881E, 0xF0CE37, 0x8FD13B, 0x5BD13B, 0x3BD17F, 0x3BA5D1, 0x2C75E1]

    static func security(_ s: Double) -> SIMD4<Float> {
        let r = C.roundSec(s)
        let hex = r <= 0 ? sec[0] : sec[min(10, Int((r * 10).rounded()))]
        return SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
    }

    static func rgba(_ c: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
