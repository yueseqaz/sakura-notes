import SwiftUI
import AppKit
import SakuraCore
import SakuraSearch

// MARK: - Graph

/// Force-directed knowledge graph over wiki links.
struct GraphWindowSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @StateObject private var graphModel = GraphModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.spaceM) {
                Text("Knowledge Graph")
                    .font(DS.title(14))
                Spacer()
                Toggle("Hide orphans", isOn: $graphModel.hideOrphans)
                    .toggleStyle(.checkbox)
                    .font(DS.caption())
                Menu {
                    Picker("Filter", selection: $graphModel.folderFilter) {
                        Text("All folders").tag("")
                        ForEach(graphModel.folders, id: \.self) { folder in
                            Text(folder.isEmpty ? "(root)" : folder).tag(folder)
                        }
                    }
                } label: {
                    Text(graphModel.folderFilter.isEmpty ? "All folders" : graphModel.folderFilter)
                        .font(DS.caption())
                }
                .frame(width: 150)
                Slider(value: $graphModel.maxNodes, in: 40...400, step: 20) {
                    Text("Max")
                }
                .frame(width: 140)
                Text("\(graphModel.nodes.count) notes")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(DS.spaceM)
            HairlineDivider()
            GraphCanvasView(graphModel: graphModel) { path in
                isPresented = false
                NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": path])
            }
            .overlay(alignment: .bottomLeading) {
                if let hovered = graphModel.hoveredNode {
                    HStack(spacing: DS.spaceXS) {
                        Image(systemName: "doc.text")
                        Text(hovered.title)
                            .font(DS.caption())
                        Text(hovered.id)
                            .font(DS.caption())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, DS.spaceM)
                    .padding(.vertical, DS.spaceS)
                    .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(.regularMaterial))
                    .padding(DS.spaceM)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            graphModel.rebuild(environment: environment)
        }
        .onChange(of: graphModel.graphVersion) { _ in
            graphModel.rebuild(environment: environment)
        }
    }
}

@MainActor
final class GraphModel: ObservableObject {
    struct Node: Identifiable {
        let id: String  // path
        var title: String
        var x: CGFloat
        var y: CGFloat
        var degree: Int = 0
    }

    struct Edge: Identifiable {
        let id: Int
        let from: Int  // node index
        let to: Int
    }

    @Published var nodes: [Node] = []
    @Published var edges: [Edge] = []
    @Published var hideOrphans = false { didSet { rebuildAll() } }
    @Published var folderFilter: String = "" { didSet { rebuildAll() } }
    @Published var maxNodes: Double = 250 { didSet { rebuildAll() } }
    @Published var hoveredNode: Node?
    @Published private(set) var graphVersion: Int = 0
    var folders: [String] = []
    /// Simulation canvas bounds, matched by the rendering view.
    static let canvasWidth: CGFloat = 660
    static let canvasHeight: CGFloat = 560

    private weak var environment: AppEnvironment?
    private var cancellable: Any?

    func rebuild(environment: AppEnvironment) {
        self.environment = environment
        if cancellable == nil {
            cancellable = environment.$graphVersion
                .receive(on: DispatchQueue.main)
                .sink { [weak self] version in
                    self?.graphVersion = version
                }
        }
        rebuildAll()
    }

    /// Rebuilds nodes and edges from the current link index (deterministic).
    private func rebuildAll() {
        guard let env = environment else { return }
        let snapshot = env.linkIndex.graphSnapshot()

        var folderSet = Set<String>()
        for (path, _, _) in snapshot {
            folderSet.insert((path as NSString).deletingLastPathComponent)
        }
        folders = folderSet.sorted()

        // 1. Filter by folder.
        var visible = snapshot.filter { (path, _, _) in
            folderFilter.isEmpty || (path as NSString).deletingLastPathComponent == folderFilter
        }

        // 2. Build resolution helpers over the visible set.
        var indexByPath: [String: Int] = [:]
        var indexByTitle: [String: Int] = [:]
        var indexByFileName: [String: Int] = [:]
        func registerIndexes() {
            indexByPath.removeAll()
            indexByTitle.removeAll()
            indexByFileName.removeAll()
            for (index, item) in visible.enumerated() {
                indexByPath[item.path] = index
                indexByTitle[item.title.lowercased(), default: index] = min(
                    indexByTitle[item.title.lowercased()] ?? Int.max, index
                )
                let fileName = (((item.path as NSString).lastPathComponent) as NSString).deletingPathExtension.lowercased()
                indexByFileName[fileName, default: index] = min(indexByFileName[fileName] ?? Int.max, index)
            }
        }
        registerIndexes()

        func resolve(_ target: String) -> Int? {
            let clean = target.trimmingCharacters(in: .whitespaces)
            if let exact = indexByPath[clean] { return exact }
            let lowered = clean.lowercased()
            if let byTitle = indexByTitle[lowered] { return byTitle }
            if let byFile = indexByFileName[lowered] { return byFile }
            return nil
        }

        // 3. Collect edges.
        var edgePairs: [(Int, Int)] = []
        var degrees = Array(repeating: 0, count: visible.count)
        for (path, _, outgoing) in visible {
            guard let from = indexByPath[path] else { continue }
            for target in outgoing {
                if let to = resolve(target), to != from {
                    edgePairs.append((from, to))
                    degrees[from] += 1
                    degrees[to] += 1
                }
            }
        }

        // 4. Cap to the most-connected nodes.
        if visible.count > Int(maxNodes) {
            let keep = Set(
                visible.enumerated()
                    .sorted { degrees[$0.offset] > degrees[$1.offset] }
                    .prefix(Int(maxNodes))
                    .map(\.element.path)
            )
            visible = visible.filter { keep.contains($0.path) }
            registerIndexes()
            edgePairs.removeAll()
            degrees = Array(repeating: 0, count: visible.count)
            for (path, _, outgoing) in visible {
                guard let from = indexByPath[path] else { continue }
                for target in outgoing {
                    if let to = resolve(target), to != from {
                        edgePairs.append((from, to))
                        degrees[from] += 1
                        degrees[to] += 1
                    }
                }
            }
        }

        // 5. Optionally drop orphans.
        if hideOrphans {
            let connected = Set(edgePairs.flatMap { [$0.0, $0.1] })
            let oldVisible = visible
            let oldIndexes = connected
            visible = visible.enumerated().filter { oldIndexes.contains($0.offset) }.map(\.element)
            registerIndexes()
            var remapped: [(Int, Int)] = []
            // Map old index → new index.
            var oldToNew: [Int: Int] = [:]
            for (newIndex, item) in visible.enumerated() {
                if let oldIndex = oldVisible.firstIndex(where: { $0.path == item.path }) {
                    oldToNew[oldIndex] = newIndex
                }
            }
            for (from, to) in edgePairs {
                if let newFrom = oldToNew[from], let newTo = oldToNew[to] {
                    remapped.append((newFrom, newTo))
                }
            }
            edgePairs = remapped
        }
        _ = degrees

        // 6. Seed positions deterministically and simulate.
        nodes = visible.enumerated().map { index, item in
            let angle = CGFloat(index) / CGFloat(max(1, visible.count)) * 2 * .pi
            let radius: CGFloat = 190
            return Node(
                id: item.path,
                title: item.title,
                x: radius * cos(angle) + Self.canvasWidth / 2,
                y: radius * sin(angle) + Self.canvasHeight / 2,
                degree: 0
            )
        }
        edges = edgePairs.enumerated().map { Edge(id: $0.offset, from: $0.element.0, to: $0.element.1) }
        simulate(iterations: 140)
    }

    /// Simple force simulation: pairwise repulsion + edge springs + centering.
    func simulate(iterations: Int) {
        let count = nodes.count
        guard count > 0 else { return }
        let repulsion: CGFloat = 13000
        let springLength: CGFloat = 115
        let springStrength: CGFloat = 0.02
        let centerPull: CGFloat = 0.004

        for _ in 0..<iterations {
            var fx = Array(repeating: CGFloat(0), count: count)
            var fy = Array(repeating: CGFloat(0), count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var dx = nodes[i].x - nodes[j].x
                    var dy = nodes[i].y - nodes[j].y
                    var distance = sqrt(dx * dx + dy * dy)
                    if distance < 1 {
                        dx = .random(in: -1...1)
                        dy = .random(in: -1...1)
                        distance = 1
                    }
                    let force = repulsion / (distance * distance)
                    fx[i] += dx / distance * force
                    fy[i] += dy / distance * force
                    fx[j] -= dx / distance * force
                    fy[j] -= dy / distance * force
                }
            }
            for edge in edges {
                guard edge.from < count, edge.to < count else { continue }
                let dx = nodes[edge.to].x - nodes[edge.from].x
                let dy = nodes[edge.to].y - nodes[edge.from].y
                let distance = max(1, sqrt(dx * dx + dy * dy))
                let force = (distance - springLength) * springStrength
                fx[edge.from] += dx / distance * force
                fy[edge.from] += dy / distance * force
                fx[edge.to] -= dx / distance * force
                fy[edge.to] -= dy / distance * force
            }
            let centerX = Self.canvasWidth / 2
            let centerY = Self.canvasHeight / 2
            for i in 0..<count {
                fx[i] += (centerX - nodes[i].x) * centerPull
                fy[i] += (centerY - nodes[i].y) * centerPull
                nodes[i].x += max(-10, min(10, fx[i]))
                nodes[i].y += max(-10, min(10, fy[i]))
            }
        }
    }
}

/// Canvas rendering of the graph with hit-testing and hover.
struct GraphCanvasView: View {
    @ObservedObject var graphModel: GraphModel
    let openNote: (String) -> Void

    private func layoutMetrics(size: CGSize) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let scaleX = size.width / GraphModel.canvasWidth
        let scaleY = size.height / GraphModel.canvasHeight
        let scale = min(scaleX, scaleY)
        let offsetX = (size.width - GraphModel.canvasWidth * scale) / 2
        let offsetY = (size.height - GraphModel.canvasHeight * scale) / 2
        return (scale, offsetX, offsetY)
    }

    private func transform(_ node: GraphModel.Node, metrics: (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat)) -> CGPoint {
        CGPoint(x: node.x * metrics.scale + metrics.offsetX, y: node.y * metrics.scale + metrics.offsetY)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = layoutMetrics(size: geometry.size)
            ZStack {
                Canvas { context, _ in
                    var path = Path()
                    for edge in graphModel.edges {
                        guard edge.from < graphModel.nodes.count, edge.to < graphModel.nodes.count else { continue }
                        path.move(to: transform(graphModel.nodes[edge.from], metrics: metrics))
                        path.addLine(to: transform(graphModel.nodes[edge.to], metrics: metrics))
                    }
                    context.stroke(path, with: .color(.primary.opacity(0.14)), lineWidth: 0.8)

                    for node in graphModel.nodes {
                        let point = transform(node, metrics: metrics)
                        let radius = max(3, min(10, CGFloat(3 + node.degree)))
                        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(0.75)))
                        if node.degree >= 3 {
                            context.draw(
                                Text(node.title).font(.system(size: 9)).foregroundColor(.primary.opacity(0.75)),
                                at: CGPoint(x: point.x, y: point.y - radius - 7)
                            )
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        graphModel.hoveredNode = hitTest(value.location, metrics: metrics)
                    }
                    .onEnded { value in
                        graphModel.hoveredNode = hitTest(value.location, metrics: metrics)
                        if let node = graphModel.hoveredNode {
                            openNote(node.id)
                        }
                    }
            )
            .overlay(alignment: .topLeading) {
                if let hovered = graphModel.hoveredNode {
                    Text("\(hovered.title)\n\(hovered.id)")
                        .font(DS.caption())
                        .padding(.horizontal, DS.spaceM)
                        .padding(.vertical, DS.spaceS)
                        .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(.regularMaterial))
                        .padding(DS.spaceM)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Maps a view-space point back into simulation space and finds the node.
    private func hitTest(_ point: CGPoint, metrics: (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat)) -> GraphModel.Node? {
        let simX = (point.x - metrics.offsetX) / metrics.scale
        let simY = (point.y - metrics.offsetY) / metrics.scale
        var best: (GraphModel.Node, CGFloat)?
        for node in graphModel.nodes {
            let dx = node.x - simX
            let dy = node.y - simY
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.1 {
                best = (node, distance)
            }
        }
        guard let (node, distance) = best, distance < 30 * 30 else { return nil }
        return node
    }
}

// MARK: - Tasks

struct TasksSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @VS private var showCompleted = false

    struct TaskRow: Identifiable {
        let id: String
        let notePath: String
        let noteTitle: String
        let task: TaskItem
    }

    private var rows: [TaskRow] {
        var result: [TaskRow] = []
        for (path, facts) in environment.factsCache.sorted(by: { $0.key < $1.key }) {
            for task in facts.tasks {
                result.append(TaskRow(
                    id: "\(path)#\(task.lineIndex)",
                    notePath: path,
                    noteTitle: facts.title ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                    task: task
                ))
            }
        }
        return result
    }

    private var visibleRows: [TaskRow] {
        showCompleted ? rows : rows.filter { !$0.task.isCompleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("All Tasks")
                    .font(DS.title(14))
                Text("\(rows.filter { !$0.task.isCompleted }.count) open")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("Show completed", isOn: $showCompleted)
                    .toggleStyle(.checkbox)
                    .font(DS.caption())
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(DS.spaceM)
            HairlineDivider()
            if visibleRows.isEmpty {
                EmptyStateView(
                    symbol: "checklist",
                    title: "No tasks found",
                    message: "Add task lists to your notes with `- [ ] item` syntax and they will aggregate here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleRows) { row in
                            Button {
                                environment.toggleTask(path: row.notePath, lineIndex: row.task.lineIndex)
                            } label: {
                                HStack(alignment: .top, spacing: DS.spaceS) {
                                    Image(systemName: row.task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(row.task.isCompleted ? .green : .secondary)
                                        .font(.system(size: 13))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.task.text)
                                            .font(DS.body(13))
                                            .strikethrough(row.task.isCompleted)
                                            .foregroundColor(row.task.isCompleted ? .secondary : .primary)
                                        HStack(spacing: DS.spaceXS) {
                                            Image(systemName: "doc")
                                                .font(.system(size: 8))
                                            Text(row.noteTitle)
                                                .lineLimit(1)
                                        }
                                        .font(DS.caption())
                                        .foregroundColor(.secondary.opacity(0.7))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, DS.spaceL)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DS.spaceS)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}
