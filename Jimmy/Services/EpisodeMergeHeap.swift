import Foundation
import os

/// Min-heap entry for episode merge - enables O(log S) k-way merge of episodes from multiple shows
struct EpisodeHeapNode: Comparable {
    let showID: UUID
    let episode: Episode
    var iterator: IndexingIterator<[Episode]>
    
    /// Min-heap comparison - newest episodes have highest priority (smallest heap value)
    /// This ensures when we pop from the heap, we get the newest episode across all shows
    static func < (lhs: EpisodeHeapNode, rhs: EpisodeHeapNode) -> Bool {
        let lhsDate = lhs.episode.publishedDate ?? Date.distantPast
        let rhsDate = rhs.episode.publishedDate ?? Date.distantPast
        // Min-heap: smaller values have higher priority
        // For newest-first, we want newer dates to be "smaller" in the heap
        return lhsDate > rhsDate
    }
    
    static func == (lhs: EpisodeHeapNode, rhs: EpisodeHeapNode) -> Bool {
        lhs.episode.id == rhs.episode.id
    }
}

/// Efficient k-way merge of episodes from multiple shows using a min-heap
/// Maintains O(log S) insertion complexity where S is the number of subscribed shows
/// This replaces the O(N log N) full array sort with incremental merging
class EpisodeMergeHeap {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "EpisodeMergeHeap")
    private var heap: [EpisodeHeapNode] = []
    private var mergedEpisodes: [Episode] = []
    
    /// Initialize heap with the first episode from each show
    /// Each show's episodes should already be sorted newest-first
    init(episodesByShow: [UUID: [Episode]]) {
        heap.reserveCapacity(episodesByShow.count)
        
        for (showID, episodes) in episodesByShow {
            guard !episodes.isEmpty else { continue }
            
            var iterator = episodes.makeIterator()
            if let firstEpisode = iterator.next() {
                let node = EpisodeHeapNode(
                    showID: showID,
                    episode: firstEpisode,
                    iterator: iterator
                )
                heap.append(node)
            }
        }
        
        // Build heap structure - O(S) operation
        buildHeap()
    }
    
    /// Merge all episodes into a single sorted array
    /// Returns episodes sorted by publish date (newest first)
    /// Time complexity: O(N log S) where N is total episodes, S is number of shows
    func mergeAll() -> [Episode] {
        mergedEpisodes.removeAll()
        mergedEpisodes.reserveCapacity(estimatedTotalEpisodes())
        
        while !heap.isEmpty {
            // Extract the newest episode (min-heap root)
            guard let newestNode = extractMin() else { break }
            mergedEpisodes.append(newestNode.episode)
            
            // Try to get the next episode from the same show
            var updatedNode = newestNode
            if let nextEpisode = updatedNode.iterator.next() {
                updatedNode = EpisodeHeapNode(
                    showID: newestNode.showID,
                    episode: nextEpisode,
                    iterator: updatedNode.iterator
                )
                insert(updatedNode)
            }
        }
        
        return mergedEpisodes
    }
    
    /// Incrementally add new episodes from a refreshed show
    /// This allows updating the merge without rebuilding the entire structure
    /// Time complexity: O(E log S) where E is episodes from the updated show
    func updateShow(_ showID: UUID, with newEpisodes: [Episode]) {
        // Remove any existing nodes for this show
        heap.removeAll { $0.showID == showID }
        buildHeap() // Rebuild heap structure after removal
        
        // Add new episodes from this show
        guard !newEpisodes.isEmpty else { return }
        
        var iterator = newEpisodes.makeIterator()
        if let firstEpisode = iterator.next() {
            let node = EpisodeHeapNode(
                showID: showID,
                episode: firstEpisode,
                iterator: iterator
            )
            insert(node)
        }
    }
    
    /// Get next batch of episodes without fully merging
    /// Useful for pagination - returns the next N newest episodes
    func getNextBatch(count: Int) -> [Episode] {
        var batch: [Episode] = []
        batch.reserveCapacity(count)
        
        for _ in 0..<count {
            guard !heap.isEmpty else { break }
            
            guard let newestNode = extractMin() else { break }
            batch.append(newestNode.episode)
            
            // Try to get the next episode from the same show
            var updatedNode = newestNode
            if let nextEpisode = updatedNode.iterator.next() {
                updatedNode = EpisodeHeapNode(
                    showID: newestNode.showID,
                    episode: nextEpisode,
                    iterator: updatedNode.iterator
                )
                insert(updatedNode)
            }
        }
        
        return batch
    }
    
    /// Check if there are more episodes available
    var hasMoreEpisodes: Bool {
        !heap.isEmpty
    }
    
    /// Get estimated total episodes for capacity planning
    private func estimatedTotalEpisodes() -> Int {
        // Rough estimate: assume average of 50 episodes per show
        return heap.count * 50
    }
    
    // MARK: - Min-Heap Operations
    
    /// Build heap structure from existing array - O(S) operation
    private func buildHeap() {
        guard heap.count > 1 else { return }
        
        // Start from the last non-leaf node and heapify down
        for i in stride(from: (heap.count / 2) - 1, through: 0, by: -1) {
            heapifyDown(from: i)
        }
    }
    
    /// Insert new node into heap - O(log S) operation
    private func insert(_ node: EpisodeHeapNode) {
        heap.append(node)
        heapifyUp(from: heap.count - 1)
    }
    
    /// Extract minimum (newest episode) from heap - O(log S) operation
    private func extractMin() -> EpisodeHeapNode? {
        guard !heap.isEmpty else {
            logger.warning("EpisodeMergeHeap: Attempted to extract from empty heap")
            return nil
        }
        
        if heap.count == 1 {
            return heap.removeLast()
        }
        
        let min = heap[0]
        heap[0] = heap.removeLast()
        heapifyDown(from: 0)
        
        return min
    }
    
    /// Restore heap property upward - O(log S) operation
    private func heapifyUp(from index: Int) {
        var currentIndex = index
        
        while currentIndex > 0 {
            let parentIndex = (currentIndex - 1) / 2
            
            if heap[currentIndex] < heap[parentIndex] {
                heap.swapAt(currentIndex, parentIndex)
                currentIndex = parentIndex
            } else {
                break
            }
        }
    }
    
    /// Restore heap property downward - O(log S) operation
    private func heapifyDown(from index: Int) {
        var currentIndex = index
        
        while true {
            let leftChild = 2 * currentIndex + 1
            let rightChild = 2 * currentIndex + 2
            var smallest = currentIndex
            
            if leftChild < heap.count && heap[leftChild] < heap[smallest] {
                smallest = leftChild
            }
            
            if rightChild < heap.count && heap[rightChild] < heap[smallest] {
                smallest = rightChild
            }
            
            if smallest != currentIndex {
                heap.swapAt(currentIndex, smallest)
                currentIndex = smallest
            } else {
                break
            }
        }
    }
} 