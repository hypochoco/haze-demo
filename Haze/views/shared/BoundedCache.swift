//
//  BoundedCache.swift
//  Haze — views/shared
//

struct BoundedCache<Key: Hashable, Value> {
    private(set) var storage: [Key: Value] = [:]
    private var order: [Key] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    var count: Int { storage.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let v = storage[key] else { return nil }
            touch(key)
            return v
        }
        set {
            if let newValue {
                storage[key] = newValue
                touch(key)
                evictIfNeeded()
            } else if storage.removeValue(forKey: key) != nil {
                if let i = order.firstIndex(of: key) { order.remove(at: i) }
            }
        }
    }

    private mutating func touch(_ key: Key) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    private mutating func evictIfNeeded() {
        while storage.count > capacity, !order.isEmpty {
            let lru = order.removeFirst()
            storage.removeValue(forKey: lru)
        }
    }
}
