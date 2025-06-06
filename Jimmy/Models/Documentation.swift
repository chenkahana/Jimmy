import Foundation

// MARK: - Documentation Models

struct DocumentationCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let files: [DocumentationFile]
    
    static func == (lhs: DocumentationCategory, rhs: DocumentationCategory) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DocumentationFile: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let filename: String
    let description: String
    let icon: String
    
    static func == (lhs: DocumentationFile, rhs: DocumentationFile) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Documentation Service

class DocumentationService: ObservableObject {
    static let shared = DocumentationService()
    
    @Published var categories: [DocumentationCategory] = []
    @Published var isLoading = false
    
    private init() {
        loadDocumentationStructure()
    }
    
    private func loadDocumentationStructure() {
        categories = [
            DocumentationCategory(
                name: "Project Documentation",
                icon: "house.fill",
                description: "Core project information and overview",
                files: [
                    DocumentationFile(
                        title: "Main README",
                        filename: "project/MAIN_README.md",
                        description: "Features overview, technology stack, and getting started",
                        icon: "house"
                    ),
                    DocumentationFile(
                        title: "Contributing Guidelines",
                        filename: "project/CONTRIBUTING.md",
                        description: "Guidelines for contributing to Jimmy",
                        icon: "person.2"
                    ),
                    DocumentationFile(
                        title: "App Summary",
                        filename: "project/APP_RENAME_SUMMARY.md",
                        description: "Brief overview of Jimmy's purpose",
                        icon: "app"
                    ),
                    DocumentationFile(
                        title: "Privacy Policy",
                        filename: "project/privacyPolicy.md",
                        description: "Data collection and privacy information",
                        icon: "hand.raised"
                    )
                ]
            ),
            
            DocumentationCategory(
                name: "Import Guides",
                icon: "arrow.down.circle.fill",
                description: "Step-by-step guides for importing subscriptions",
                files: [
                    DocumentationFile(
                        title: "Apple Podcasts Import",
                        filename: "import-guides/APPLE_PODCASTS_IMPORT.md",
                        description: "Import all your Apple Podcasts subscriptions",
                        icon: "applelogo"
                    ),
                    DocumentationFile(
                        title: "Spotify Import",
                        filename: "import-guides/SPOTIFY_IMPORT.md",
                        description: "Import followed podcasts from Spotify",
                        icon: "music.note"
                    ),
                    DocumentationFile(
                        title: "Feedback Script",
                        filename: "import-guides/GOOGLE_SHEETS_FEEDBACK_SCRIPT.md",
                        description: "Google Sheets feedback integration",
                        icon: "doc.text"
                    )
                ]
            ),
            
            DocumentationCategory(
                name: "Features",
                icon: "star.fill",
                description: "Feature specifications and usage guides",
                files: [
                    DocumentationFile(
                        title: "Episode View Implementation",
                        filename: "features/EPISODE_VIEW_IMPLEMENTATION.md",
                        description: "Enhanced episode view and interactions",
                        icon: "play.rectangle"
                    ),
                    DocumentationFile(
                        title: "Episode Cache System",
                        filename: "features/EPISODE_CACHE_README.md",
                        description: "Caching system for better performance",
                        icon: "externaldrive"
                    ),
                    DocumentationFile(
                        title: "Shake to Undo",
                        filename: "features/SHAKE_TO_UNDO_README.md",
                        description: "Undo actions by shaking your device",
                        icon: "arrow.uturn.backward"
                    ),
                    DocumentationFile(
                        title: "Image Caching System",
                        filename: "features/CACHING_SYSTEM_README.md",
                        description: "Comprehensive image and data caching",
                        icon: "photo"
                    ),
                    DocumentationFile(
                        title: "Loading Improvements",
                        filename: "features/LOADING_IMPROVEMENTS_SUMMARY.md",
                        description: "Performance improvements and faster loading",
                        icon: "speedometer"
                    )
                ]
            ),
            
            DocumentationCategory(
                name: "Technical Guides",
                icon: "gearshape.fill",
                description: "Advanced technical documentation",
                files: [
                    DocumentationFile(
                        title: "UserDefaults Storage Fix",
                        filename: "technical/USERDEFAULTS_STORAGE_FIX.md",
                        description: "Migration to file-based storage",
                        icon: "internaldrive"
                    ),
                    DocumentationFile(
                        title: "Apple Watch Setup",
                        filename: "technical/WATCH_README.md",
                        description: "Apple Watch companion app",
                        icon: "applewatch"
                    ),
                    DocumentationFile(
                        title: "Feature Summary",
                        filename: "technical/FEATURE_SUMMARY.md",
                        description: "Comprehensive feature overview",
                        icon: "list.bullet"
                    ),
                    DocumentationFile(
                        title: "Artwork Guidelines",
                        filename: "technical/ARTWORK_USAGE_GUIDELINES.md",
                        description: "Consistent artwork usage rules",
                        icon: "photo.artframe"
                    )
                ]
            ),
            
            DocumentationCategory(
                name: "Development",
                icon: "hammer.fill",
                description: "Build instructions and troubleshooting",
                files: [
                    DocumentationFile(
                        title: "Build Status & Troubleshooting",
                        filename: "development/BUILD_STATUS.md",
                        description: "Build fixes and troubleshooting guide",
                        icon: "wrench.and.screwdriver"
                    ),
                    DocumentationFile(
                        title: "Jimmy Module README",
                        filename: "development/JIMMY_MODULE_README.md",
                        description: "Technical architecture and implementation",
                        icon: "cube"
                    )
                ]
            ),
            
            DocumentationCategory(
                name: "Releases",
                icon: "tag.fill",
                description: "Version history and release notes",
                files: [
                    DocumentationFile(
                        title: "Version 2 Release Notes",
                        filename: "releases/RELEASE_NOTES_v2.md",
                        description: "Latest release focusing on stability",
                        icon: "doc.text"
                    ),
                    DocumentationFile(
                        title: "Version 1",
                        filename: "releases/v1.md",
                        description: "Initial fully functional release",
                        icon: "1.circle"
                    ),
                    DocumentationFile(
                        title: "Version 2",
                        filename: "releases/v2.md",
                        description: "Stability improvements and new features",
                        icon: "2.circle"
                    )
                ]
            )
        ]
    }
    
    func loadDocumentationContent(for file: DocumentationFile) -> String? {
        // Try to read from app bundle first (for production builds)
        if let bundleContent = loadFromBundle(file: file) {
            return bundleContent
        }
        
        // For development, try to read from workspace
        return loadFromWorkspace(file: file) ?? generatePlaceholderContent(for: file)
    }
    
    private func loadFromWorkspace(file: DocumentationFile) -> String? {
        // Get the current working directory and construct path to docs
        let currentDir = FileManager.default.currentDirectoryPath
        let workspacePath = URL(fileURLWithPath: currentDir)
            .appendingPathComponent("docs")
            .appendingPathComponent(file.filename)
        
        if FileManager.default.fileExists(atPath: workspacePath.path) {
            return try? String(contentsOf: workspacePath)
        }
        
        // Try alternative paths for development
        let alternativePaths = [
            "/Users/chenk/Jimmy/docs/\(file.filename)",
            "./docs/\(file.filename)",
            "../docs/\(file.filename)"
        ]
        
        for path in alternativePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return try? String(contentsOf: url)
            }
        }
        
        return nil
    }
    
    private func generatePlaceholderContent(for file: DocumentationFile) -> String {
        return """
# \(file.title)

*This documentation file is currently being loaded.*

## Description
\(file.description)

## Status
This documentation is part of the Jimmy podcast app. The file should be located at:
`docs/\(file.filename)`

If you're seeing this placeholder, the documentation file may not be properly bundled with the app or there may be a loading issue.

## Quick Help
- **Import Guides**: Step-by-step instructions for importing podcasts from various platforms
- **Features**: Detailed guides on app features and functionality  
- **Technical**: Advanced technical documentation for developers
- **Project**: General project information and policies

For the most up-to-date documentation, visit the Jimmy project repository.
"""
    }
    
    private func loadFromBundle(file: DocumentationFile) -> String? {
        // Try with docs prefix
        if let url = Bundle.main.url(forResource: "docs/\(file.filename.replacingOccurrences(of: ".md", with: ""))", withExtension: "md") {
            return try? String(contentsOf: url)
        }
        
        // Try without docs prefix
        if let url = Bundle.main.url(forResource: file.filename.replacingOccurrences(of: ".md", with: ""), withExtension: "md") {
            return try? String(contentsOf: url)
        }
        
        // Try with just the filename
        let filename = URL(fileURLWithPath: file.filename).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        if let url = Bundle.main.url(forResource: filename, withExtension: "md") {
            return try? String(contentsOf: url)
        }
        
        return nil
    }
} 