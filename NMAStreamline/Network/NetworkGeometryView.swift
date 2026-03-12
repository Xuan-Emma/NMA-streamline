import SwiftUI

/// Node-and-edge network geometry preview for the NMA.
/// Visualizes which treatments have been directly or indirectly compared
/// in the included studies, and warns when a "linker" study is at risk.
struct NetworkGeometryView: View {
    let project: NMAProject

    @State private var selectedNode: String?
    @State private var layoutPositions: [String: CGPoint] = [:]
    @State private var hasLayout = false

    private var network: NMANetwork { NMANetwork(project: project) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                networkCanvas
                if network.nodes.isEmpty { emptyState }
            }
            Divider()
            statsBar
        }
        .onAppear { computeLayout() }
        .onChange(of: project.studies.count) { _, _ in computeLayout() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Label("Network Geometry", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Spacer()
            Button("Refresh") { computeLayout() }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Canvas

    private var networkCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                // Edges
                ForEach(network.edges, id: \.id) { edge in
                    edgeView(edge, in: geometry.size)
                }
                // Nodes
                ForEach(network.nodes, id: \.self) { node in
                    nodeView(node, in: geometry.size)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func nodeView(_ name: String, in size: CGSize) -> some View {
        let pos = nodePosition(name, in: size)
        let degree = network.degree(of: name)
        let isLinker = network.isLinker(name)
        let isSelected = selectedNode == name
        let isAtRisk = network.isAtRisk(name)

        return Button(action: { selectedNode = (selectedNode == name ? nil : name) }) {
            VStack(spacing: 4) {
                Circle()
                    .fill(nodeColor(isLinker: isLinker, isAtRisk: isAtRisk, isSelected: isSelected))
                    .frame(width: nodeRadius(degree), height: nodeRadius(degree))
                    .overlay(
                        Circle().stroke(isSelected ? Color.white : .clear, lineWidth: 2)
                    )
                    .shadow(color: isAtRisk ? .red.opacity(0.6) : .clear, radius: 8)

                Text(name)
                    .font(.caption.bold())
                    .foregroundStyle(isAtRisk ? .red : .primary)
                    .shadow(color: .white, radius: 2)
            }
        }
        .buttonStyle(.plain)
        .position(pos)
    }

    private func edgeView(_ edge: NetworkEdge, in size: CGSize) -> some View {
        let from = nodePosition(edge.from, in: size)
        let to   = nodePosition(edge.to,   in: size)

        return Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            edgeColor(edge),
            style: StrokeStyle(lineWidth: CGFloat(edge.studyCount) + 1, lineCap: .round)
        )
        .overlay(
            edgeLabel(edge, from: from, to: to)
        )
    }

    private func edgeLabel(_ edge: NetworkEdge, from: CGPoint, to: CGPoint) -> some View {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        return Text("\(edge.studyCount)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(4)
            .background(edgeColor(edge).opacity(0.85))
            .cornerRadius(4)
            .position(mid)
    }

    // MARK: - Stats bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem("Nodes (Treatments)", "\(network.nodes.count)")
            statItem("Edges (Comparisons)", "\(network.edges.count)")
            statItem("Total Studies", "\(project.finalIncluded)")
            statItem("Connected", network.isConnected ? "Yes ✓" : "No ✗")

            if !network.atRiskNodes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text("Linker studies at risk: \(network.atRiskNodes.joined(separator: ", "))")
                        .foregroundStyle(.red)
                }
                .font(.caption.bold())
            }

            Spacer()
        }
        .padding()
        .background(.background.secondary)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Network Data",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("Include studies to build the network geometry preview.")
        )
    }

    // MARK: - Layout computation (circular spring)

    /// Number of spring-relaxation iterations. More iterations → smoother layout,
    /// but higher CPU cost. 20 is a good balance for typical network sizes (< 30 nodes).
    private let springIterations = 20

    private func computeLayout() {
        let nodes = network.nodes
        guard !nodes.isEmpty else { hasLayout = false; return }

        let count = nodes.count
        var positions: [String: CGPoint] = [:]

        // Initial circular placement
        for (i, node) in nodes.enumerated() {
            let angle = 2 * Double.pi * Double(i) / Double(count) - Double.pi / 2
            let x = 0.5 + 0.35 * cos(angle)
            let y = 0.5 + 0.35 * sin(angle)
            positions[node] = CGPoint(x: x, y: y)
        }

        // Spring-based relaxation
        for _ in 0..<springIterations {
            positions = springStep(positions, edges: network.edges)
        }

        layoutPositions = positions
        hasLayout = true
    }

    private func springStep(
        _ positions: [String: CGPoint],
        edges: [NetworkEdge]
    ) -> [String: CGPoint] {
        var forces: [String: CGVector] = Dictionary(uniqueKeysWithValues: positions.keys.map { ($0, CGVector.zero) })
        let k = 0.05

        // Repulsion between all node pairs
        let keys = Array(positions.keys)
        for i in 0..<keys.count {
            for j in (i+1)..<keys.count {
                let a = keys[i], b = keys[j]
                guard let pa = positions[a], let pb = positions[b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                let dist = max(sqrt(dx*dx + dy*dy), 0.01)
                let rep  = k / (dist * dist)
                forces[a]! += CGVector(dx: rep * dx / dist, dy: rep * dy / dist)
                forces[b]! += CGVector(dx: -rep * dx / dist, dy: -rep * dy / dist)
            }
        }

        // Attraction along edges
        for edge in edges {
            guard let pa = positions[edge.from], let pb = positions[edge.to] else { continue }
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let dist = max(sqrt(dx*dx + dy*dy), 0.01)
            let att  = k * dist
            forces[edge.from]! += CGVector(dx: att * dx / dist, dy: att * dy / dist)
            forces[edge.to]!   += CGVector(dx: -att * dx / dist, dy: -att * dy / dist)
        }

        // Apply forces
        var next = positions
        for key in keys {
            let f = forces[key]!
            let p = positions[key]!
            next[key] = CGPoint(
                x: min(max(p.x + f.dx, 0.05), 0.95),
                y: min(max(p.y + f.dy, 0.05), 0.95)
            )
        }
        return next
    }

    private func nodePosition(_ name: String, in size: CGSize) -> CGPoint {
        let rel = layoutPositions[name] ?? CGPoint(x: 0.5, y: 0.5)
        return CGPoint(x: rel.x * size.width, y: rel.y * size.height)
    }

    // MARK: - Styling helpers

    private func nodeRadius(_ degree: Int) -> CGFloat {
        CGFloat(max(24, min(56, 20 + degree * 5)))
    }

    private func nodeColor(isLinker: Bool, isAtRisk: Bool, isSelected: Bool) -> Color {
        if isAtRisk    { return .red }
        if isLinker    { return .orange }
        if isSelected  { return .blue }
        return .teal
    }

    private func edgeColor(_ edge: NetworkEdge) -> Color {
        edge.isIndirect ? .orange.opacity(0.5) : .blue.opacity(0.6)
    }
}

// MARK: - CGVector helpers

private extension CGVector {
    static var zero: CGVector { CGVector(dx: 0, dy: 0) }
    static func += (lhs: inout CGVector, rhs: CGVector) {
        lhs = CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }
}

// MARK: - Network model

struct NetworkEdge: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let studyCount: Int
    let isIndirect: Bool
}

struct NMANetwork {
    let nodes: [String]
    let edges: [NetworkEdge]

    init(project: NMAProject) {
        var treatments = Set<String>()
        var edgeCounts: [Set<String>: Int] = [:]

        // Extract arms from study titles (heuristic) or from PICO interventions
        let pico = project.picoCriteria
        let knownTreatments = (pico?.intervention ?? []) + (pico?.comparator ?? [])

        for study in project.studies where study.status == .included {
            let abstract = study.abstract.lowercased()
            var studyTreatments: [String] = []

            for tx in knownTreatments where abstract.contains(tx.lowercased()) {
                studyTreatments.append(tx)
                treatments.insert(tx)
            }

            // Create edges for all treatment pairs in this study
            let unique = Array(Set(studyTreatments))
            for i in 0..<unique.count {
                for j in (i+1)..<unique.count {
                    let key: Set<String> = [unique[i], unique[j]]
                    edgeCounts[key, default: 0] += 1
                }
            }
        }

        self.nodes = Array(treatments).sorted()
        self.edges = edgeCounts.map { pair, count in
            let sorted = pair.sorted()
            return NetworkEdge(from: sorted[0], to: sorted[1], studyCount: count, isIndirect: false)
        }
    }

    func degree(of node: String) -> Int {
        edges.filter { $0.from == node || $0.to == node }.count
    }

    func isLinker(_ node: String) -> Bool {
        // A node is a linker if it connects otherwise disconnected components
        degree(of: node) >= 2
    }

    var atRiskNodes: [String] {
        nodes.filter { isAtRisk($0) }
    }

    func isAtRisk(_ node: String) -> Bool {
        // A node is "at risk" if removing it would disconnect the network
        guard nodes.count > 1 else { return false }
        let withoutNode = nodes.filter { $0 != node }
        let edgesWithout = edges.filter { $0.from != node && $0.to != node }
        return !isConnectedSubgraph(nodes: withoutNode, edges: edgesWithout) && isLinker(node)
    }

    var isConnected: Bool {
        isConnectedSubgraph(nodes: nodes, edges: edges)
    }

    private func isConnectedSubgraph(nodes: [String], edges: [NetworkEdge]) -> Bool {
        guard !nodes.isEmpty else { return true }
        var visited = Set<String>()
        var queue = [nodes[0]]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            let neighbors = edges
                .filter { $0.from == current || $0.to == current }
                .map { $0.from == current ? $0.to : $0.from }
                .filter { nodes.contains($0) }
            queue.append(contentsOf: neighbors)
        }
        return visited.count == nodes.count
    }
}
