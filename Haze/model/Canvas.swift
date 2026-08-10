//
//  Canvas.swift
//  Haze — model
//

enum CanvasBackground: String, CaseIterable {
    case white, transparent
    var title: String { self == .white ? "White" : "Transparent" }
}

struct Canvas: Equatable {
    let id: CanvasID
    var name: String
    var width: Int
    var height: Int
    var nodes: [LayerNode]
    var selectedLayerID: LayerID?
    var colorMode: ColorMode
    var dpi: Double = 72
    var pixelSelection: SelectionState = .none

    init(id: CanvasID = CanvasID(),
         name: String = "Untitled",
         width: Int,
         height: Int,
         layers: [Layer] = [],
         selectedLayerID: LayerID? = nil,
         colorMode: ColorMode = .default,
         dpi: Double = 72) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.nodes = layers.map { .layer($0) }
        self.selectedLayerID = selectedLayerID
        self.colorMode = colorMode
        self.dpi = dpi
    }

    init(id: CanvasID = CanvasID(),
         name: String = "Untitled",
         width: Int,
         height: Int,
         nodes: [LayerNode],
         selectedLayerID: LayerID? = nil,
         colorMode: ColorMode = .default,
         dpi: Double = 72) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.nodes = nodes
        self.selectedLayerID = selectedLayerID
        self.colorMode = colorMode
        self.dpi = dpi
    }

    static func makeDefault(width: Int, height: Int) -> Canvas {
        let base = Layer(name: "Background")
        return Canvas(width: width, height: height, layers: [base], selectedLayerID: base.id)
    }

    var layers: [Layer] { nodes.leaves }

    func layer(_ id: LayerID) -> Layer? { nodes.findLayer(id) }
    var selectedLayer: Layer? { selectedLayerID.flatMap(layer) }

    mutating func updateLayer(_ id: LayerID, _ transform: (inout Layer) -> Void) {
        _ = nodes.updateLayer(id, transform)
    }
    mutating func updateGroup(_ id: LayerID, _ transform: (inout LayerGroup) -> Void) {
        _ = nodes.updateGroup(id, transform)
    }
}
