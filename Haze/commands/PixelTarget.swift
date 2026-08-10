//
//  PixelTarget.swift
//  Haze — commands
//

enum PixelTarget: Hashable {
    case layer(LayerID)

    var layerID: LayerID? {
        switch self {
        case .layer(let id): return id
        }
    }
}
