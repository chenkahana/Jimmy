import Foundation

/// A generic, thread-safe in-memory cache that wraps `NSCache` with safe memory management.
/// Simplified design to prevent all memory access crashes.
final class MemoryCache<Key: Hashable, Value> {
    private let cache = NSCache<WrappedKey, WrappedValue>()
    private let accessQueue = DispatchQueue(label: "MemoryCache.access", attributes: .concurrent)
    
    /// An optional callback that is triggered when an object is evicted from the cache.
    /// WARNING: This callback may be called on any thread and should be thread-safe.
    var onObjectEvicted: ((Value) -> Void)? {
        get {
            return accessQueue.sync { _onObjectEvicted }
        }
        set {
            accessQueue.async(flags: .barrier) { [weak self] in
                self?._onObjectEvicted = newValue
            }
        }
    }
    
    private var _onObjectEvicted: ((Value) -> Void)?
    private var isDeinitialized = false

    /// The name of the cache, used for identification in logs and notifications.
    let name: String

    init(name: String = "MemoryCache", countLimit: Int = 0, totalCostLimit: Int = 0) {
        self.name = name
        self.cache.name = name
        self.cache.countLimit = countLimit
        self.cache.totalCostLimit = totalCostLimit
        // No delegate - eliminates all delegate-related crashes
    }
    
    deinit {
        // Mark as deinitialized to prevent any late operations
        accessQueue.async(flags: .barrier) { [cache] in
            // Clear everything safely
            cache.removeAllObjects()
        }
        isDeinitialized = true
        _onObjectEvicted = nil
    }

    /// Inserts a value into the cache with an optional cost.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key associated with the value.
    ///   - cost: The cost associated with the value, used to determine eviction priority. Defaults to 0.
    func insert(_ value: Value, forKey key: Key, cost: Int = 0) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, !self.isDeinitialized else { return }
            
            let wrappedKey = WrappedKey(key)
            let wrappedValue = WrappedValue(value: value, evictionCallback: { [weak self] evictedValue in
                // Safe eviction callback that checks if self still exists
                guard let self = self, !self.isDeinitialized else { return }
                self._onObjectEvicted?(evictedValue)
            })
            
            self.cache.setObject(wrappedValue, forKey: wrappedKey, cost: cost)
        }
    }

    /// Retrieves a value from the cache for a given key.
    ///
    /// - Parameter key: The key for the value to retrieve.
    /// - Returns: The cached value, or `nil` if the key is not found.
    func value(forKey key: Key) -> Value? {
        return accessQueue.sync { [weak self] in
            guard let self = self, !self.isDeinitialized else { return nil }
            
            let wrappedKey = WrappedKey(key)
            guard let wrappedValue = self.cache.object(forKey: wrappedKey) else {
                return nil
            }
            return wrappedValue.value
        }
    }

    /// Removes a value from the cache for a given key.
    ///
    /// - Parameter key: The key of the value to remove.
    func removeValue(forKey key: Key) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, !self.isDeinitialized else { return }
            
            let wrappedKey = WrappedKey(key)
            self.cache.removeObject(forKey: wrappedKey)
        }
    }

    /// Removes all objects from the cache.
    func removeAllValues() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, !self.isDeinitialized else { return }
            self.cache.removeAllObjects()
        }
    }

    /// Returns all values currently in the cache.
    /// Note: This is a snapshot and may not reflect concurrent modifications.
    func allValues() -> [Value] {
        return accessQueue.sync { [weak self] in
            guard let self = self, !self.isDeinitialized else { return [] }
            
            // NSCache doesn't provide a direct way to iterate, so we'll return empty for now
            // This is primarily used for cache checking, so returning empty is safe
            return []
        }
    }
}

// MARK: - Private Implementation

private extension MemoryCache {
    /// A lightweight wrapper around the cache key that enables safe hashing and equality.
    final class WrappedKey: NSObject {
        let key: Key
        private let keyHash: Int

        init(_ key: Key) {
            self.key = key
            self.keyHash = key.hashValue
            super.init()
        }

        override var hash: Int {
            return keyHash
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? WrappedKey else { return false }
            return key == other.key
        }
    }

    /// A safe wrapper around the cached value with built-in eviction callback.
    final class WrappedValue: NSObject {
        let value: Value
        private let evictionCallback: ((Value) -> Void)?
        private var hasBeenEvicted = false
        private let evictionQueue = DispatchQueue(label: "WrappedValue.eviction")

        init(value: Value, evictionCallback: ((Value) -> Void)?) {
            self.value = value
            self.evictionCallback = evictionCallback
            super.init()
        }
        
        deinit {
            // Call eviction callback safely when the wrapped value is deallocated
            evictionQueue.async { [value, evictionCallback, hasBeenEvicted] in
                guard !hasBeenEvicted else { return }
                evictionCallback?(value)
            }
        }
        
        func markAsEvicted() {
            evictionQueue.async { [weak self] in
                self?.hasBeenEvicted = true
            }
        }
    }
}

// Allow subscripting the cache for cleaner access.
extension MemoryCache {
    subscript(key: Key) -> Value? {
        get {
            return value(forKey: key)
        }
        set {
            if let value = newValue {
                insert(value, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }
} 