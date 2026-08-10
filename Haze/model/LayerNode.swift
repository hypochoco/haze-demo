//
//  LayerNode.swift
//  Haze — model
//

struct LayerGroup: Identifiable, Equatable {
    let id: LayerID
    var name: String
    var isVisible: Bool
    var opacity: Float
    var blend: BlendMode
    var isExpanded: Bool
    var children: [LayerNode]

    init(id: LayerID = LayerID(), name: String, isVisible: Bool = true, opacity: Float = 1,
         blend: BlendMode = .normal, isExpanded: Bool = true, children: [LayerNode] = []) {
        self.id = id; self.name = name; self.isVisible = isVisible; self.opacity = opacity
        self.blend = blend; self.isExpanded = isExpanded; self.children = children
    }
}

enum LayerNode: Identifiable, Equatable {
    case layer(Layer)
    case group(LayerGroup)

    var id: LayerID {
        switch self { case .layer(let l): return l.id; case .group(let g): return g.id }
    }
    var isGroup: Bool { if case .group = self { return true } else { return false } }
    var asLayer: Layer? { if case .layer(let l) = self { return l } else { return nil } }
    var asGroup: LayerGroup? { if case .group(let g) = self { return g } else { return nil } }
    var name: String {
        switch self { case .layer(let l): return l.name; case .group(let g): return g.name }
    }
    var isVisible: Bool {
        switch self { case .layer(let l): return l.isVisible; case .group(let g): return g.isVisible }
    }
    var opacity: Float {
        switch self { case .layer(let l): return l.opacity; case .group(let g): return g.opacity }
    }
    var blend: BlendMode {
        switch self { case .layer(let l): return l.blend; case .group(let g): return g.blend }
    }
}

extension Array where Element == LayerNode {

    var leaves: [Layer] {
        reduce(into: []) { acc, n in
            switch n {
            case .layer(let l): acc.append(l)
            case .group(let g): acc.append(contentsOf: g.children.leaves)
            }
        }
    }

    func findLayer(_ id: LayerID) -> Layer? { leaves.first { $0.id == id } }

    func allNodeIDs() -> [LayerID] {
        reduce(into: []) { acc, n in
            acc.append(n.id)
            if case .group(let g) = n { acc.append(contentsOf: g.children.allNodeIDs()) }
        }
    }

    func allNames() -> [String] {
        reduce(into: []) { acc, n in
            acc.append(n.name)
            if case .group(let g) = n { acc.append(contentsOf: g.children.allNames()) }
        }
    }

    func visibleOrderIDs() -> [LayerID] {
        reduce(into: []) { acc, n in
            acc.append(n.id)
            if case .group(let g) = n, g.isExpanded { acc.append(contentsOf: g.children.visibleOrderIDs()) }
        }
    }

    func flattenVisibleSurvivors() -> [LayerNode] {
        reduce(into: []) { acc, n in
            switch n {
            case .layer(let l):
                if !l.isVisible { acc.append(.layer(l)) }
            case .group(let g):
                if !g.isVisible {
                    acc.append(.group(g))
                } else {
                    let kids = g.children.flattenVisibleSurvivors()
                    if !kids.isEmpty { var gg = g; gg.children = kids; acc.append(.group(gg)) }
                }
            }
        }
    }

    func firstTopLevelIndex(of id: LayerID) -> Int? { firstIndex { $0.id == id } }

    func contains(nodeID id: LayerID) -> Bool {
        for n in self {
            if n.id == id { return true }
            if case .group(let g) = n, g.children.contains(nodeID: id) { return true }
        }
        return false
    }

    @discardableResult
    mutating func updateLayer(_ id: LayerID, _ transform: (inout Layer) -> Void) -> Bool {
        for i in indices {
            switch self[i] {
            case .layer(var l):
                if l.id == id { transform(&l); self[i] = .layer(l); return true }
            case .group(var g):
                if g.children.updateLayer(id, transform) { self[i] = .group(g); return true }
            }
        }
        return false
    }

    @discardableResult
    mutating func updateGroup(_ id: LayerID, _ transform: (inout LayerGroup) -> Void) -> Bool {
        for i in indices {
            if case .group(var g) = self[i] {
                if g.id == id { transform(&g); self[i] = .group(g); return true }
                if g.children.updateGroup(id, transform) { self[i] = .group(g); return true }
            }
        }
        return false
    }

    @discardableResult
    mutating func removeByID(_ id: LayerID) -> LayerNode? {
        for i in indices {
            if self[i].id == id { return remove(at: i) }
            if case .group(var g) = self[i] {
                if let removed = g.children.removeByID(id) { self[i] = .group(g); return removed }
            }
        }
        return nil
    }

    mutating func move(nodeID id: LayerID, to index: Int) {
        guard let from = firstIndex(where: { $0.id == id }) else { return }
        let node = remove(at: from)
        let dest = Swift.max(0, Swift.min(index, count))
        insert(node, at: dest)
    }

    // MARK: - Index-path ops (arbitrary-depth reparent)

    func indexPath(of id: LayerID) -> [Int]? {
        for i in indices {
            if self[i].id == id { return [i] }
            if case .group(let g) = self[i], let sub = g.children.indexPath(of: id) { return [i] + sub }
        }
        return nil
    }

    func parentPath(of id: LayerID) -> [Int]? {
        guard var p = indexPath(of: id) else { return nil }
        p.removeLast(); return p
    }

    func node(atPath path: [Int]) -> LayerNode? {
        guard let first = path.first, indices.contains(first) else { return nil }
        if path.count == 1 { return self[first] }
        guard case .group(let g) = self[first] else { return nil }
        var rest = path; rest.removeFirst()
        return g.children.node(atPath: rest)
    }

    @discardableResult
    mutating func removeNode(atPath path: [Int]) -> LayerNode? {
        guard let first = path.first, indices.contains(first) else { return nil }
        if path.count == 1 { return remove(at: first) }
        guard case .group(var g) = self[first] else { return nil }
        var rest = path; rest.removeFirst()
        let removed = g.children.removeNode(atPath: rest)
        self[first] = .group(g)
        return removed
    }

    mutating func insertNode(_ node: LayerNode, atPath path: [Int]) {
        guard let idx = path.last else { return }
        if path.count == 1 { insert(node, at: Swift.max(0, Swift.min(idx, count))); return }
        let head = path[0]
        guard indices.contains(head), case .group(var g) = self[head] else { return }
        var rest = path; rest.removeFirst()
        g.children.insertNode(node, atPath: rest)
        self[head] = .group(g)
    }

    func subtree(_ ancestorID: LayerID, contains descendantID: LayerID) -> Bool {
        guard let path = indexPath(of: ancestorID), let n = node(atPath: path),
              case .group(let g) = n else { return false }
        return g.children.contains(nodeID: descendantID)
    }

    // MARK: - Drag / reparent moves (paths computed AFTER removal → no index-shift bugs)

    mutating func moveNode(_ id: LayerID, intoGroup groupID: LayerID) {
        guard id != groupID, !subtree(id, contains: groupID) else { return }
        guard let node = removeByID(id) else { return }
        if !insertIntoGroup(groupID, node) { append(node) }
    }

    mutating func moveNode(_ id: LayerID, relativeTo targetID: LayerID, below: Bool) {
        guard id != targetID, !subtree(id, contains: targetID) else { return }
        guard let node = removeByID(id) else { return }
        guard var dest = indexPath(of: targetID) else { append(node); return }
        if below { dest[dest.count - 1] += 1 }
        insertNode(node, atPath: dest)
    }

    @discardableResult
    private mutating func insertIntoGroup(_ groupID: LayerID, _ node: LayerNode) -> Bool {
        for i in indices {
            if case .group(var g) = self[i] {
                if g.id == groupID { g.children.append(node); self[i] = .group(g); return true }
                if g.children.insertIntoGroup(groupID, node) { self[i] = .group(g); return true }
            }
        }
        return false
    }
}
