import Foundation
import SwiftUI

/// Centralized task cancellation manager
/// Implements Phase 6 requirement: "Remove blocking calls; cancel Tasks on disappear"
@MainActor
final class TaskCancellationManager: ObservableObject {
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var taskGroups: [String: Set<String>] = [:]
    
    /// Register a task with automatic cancellation management
    /// - Parameters:
    ///   - task: The task to manage
    ///   - id: Unique identifier for the task
    ///   - group: Optional group name for batch operations
    func registerTask(_ task: Task<Void, Never>, id: String, group: String? = nil) {
        // Cancel existing task with same ID
        if let existingTask = activeTasks[id] {
            existingTask.cancel()
        }
        
        activeTasks[id] = task
        
        // Add to group if specified
        if let group = group {
            taskGroups[group, default: Set()].insert(id)
        }
        // Auto-cleanup when task completes
        Task {
            await task.value
            self.unregisterTask(id: id)
        }
    }
    
    /// Cancel a specific task
    /// - Parameter id: Task identifier
    func cancelTask(id: String) {
        guard let task = activeTasks[id] else {
            return
        }
        
        task.cancel()
        unregisterTask(id: id)
    }
    
    /// Cancel all tasks in a group
    /// - Parameter group: Group name
    func cancelGroup(_ group: String) {
        guard let taskIds = taskGroups[group] else {
            return
        }
        
        for taskId in taskIds {
            if let task = activeTasks[taskId] {
                task.cancel()
                unregisterTask(id: taskId)
            }
        }
        
        taskGroups.removeValue(forKey: group)
    }
    
    /// Cancel all active tasks
    func cancelAllTasks() {
        let taskCount = activeTasks.count
        
        for (_, task) in activeTasks {
            task.cancel()
        }
        
        activeTasks.removeAll()
        taskGroups.removeAll()
        
    }
    
    /// Get active task count
    var activeTaskCount: Int {
        activeTasks.count
    }
    
    /// Get active task IDs
    var activeTaskIds: [String] {
        Array(activeTasks.keys)
    }
    
    private func unregisterTask(id: String) {
        activeTasks.removeValue(forKey: id)
        
        // Remove from all groups
        for (groupName, taskIds) in taskGroups {
            if taskIds.contains(id) {
                taskGroups[groupName]?.remove(id)
                if taskGroups[groupName]?.isEmpty == true {
                    taskGroups.removeValue(forKey: groupName)
                }
            }
        }
        
    }
    
    deinit {
        Task { [weak self] in
            await self?.cancelAllTasks()
        }
    }
}

// MARK: - Task Extensions

extension Task where Success == Void, Failure == Never {
    /// Create a managed task that automatically registers with TaskCancellationManager
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - group: Optional group name
    ///   - manager: Task cancellation manager
    ///   - operation: The async operation to perform
    /// - Returns: The created task
    @MainActor
    static func managed(
        id: String,
        group: String? = nil,
        manager: TaskCancellationManager,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let task = Task {
            await operation()
        }
        
        manager.registerTask(task, id: id, group: group)
        return task
    }
}

// MARK: - ViewModel Protocol

/// Protocol for ViewModels that need task cancellation management
protocol TaskManagedViewModel: AnyObject {
    var taskManager: TaskCancellationManager { get }
    
    /// Called when view appears - override to start tasks
    func onViewAppear() async
    
    /// Called when view disappears - automatically cancels all tasks
    func onViewDisappear() async
}

extension TaskManagedViewModel {
    @MainActor
    func onViewDisappear() async {
        taskManager.cancelAllTasks()
    }
}

// MARK: - View Modifier

struct TaskLifecycleModifier: ViewModifier {
    let viewModel: any TaskManagedViewModel
    
    func body(content: Content) -> some View {
        content
            .task {
                await viewModel.onViewAppear()
            }
            .onDisappear {
                Task {
                    await viewModel.onViewDisappear()
                }
            }
    }
}

extension View {
    /// Add automatic task lifecycle management to a view
    /// - Parameter viewModel: ViewModel conforming to TaskManagedViewModel
    /// - Returns: Modified view with task lifecycle management
    func taskLifecycle<VM: TaskManagedViewModel>(_ viewModel: VM) -> some View {
        modifier(TaskLifecycleModifier(viewModel: viewModel))
    }
}
