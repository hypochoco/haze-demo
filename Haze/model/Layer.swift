//
//  Layer.swift
//  Haze — model
//

struct Layer: Identifiable, Equatable {
    let id: LayerID
    var name: String
    var isVisible: Bool
    var opacity: Float
    var blend: BlendMode

    init(id: LayerID = LayerID(),
         name: String,
         isVisible: Bool = true,
         opacity: Float = 1,
         blend: BlendMode = .normal) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.opacity = opacity
        self.blend = blend
    }
}

extension Array where Element == Layer {
    mutating func move(id: LayerID, to index: Int) {
        guard let from = firstIndex(where: { $0.id == id }) else { return }
        let layer = remove(at: from)
        let dest = Swift.max(0, Swift.min(index, count))
        insert(layer, at: dest)
    }
}
