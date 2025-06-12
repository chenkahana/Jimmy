import SwiftUI

struct DocumentationView: View {
    @ObservedObject private var documentationService = DocumentationService.shared
    @State private var selectedCategory: DocumentationCategory?
    @State private var selectedFile: DocumentationFile?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(documentationService.categories) { category in
                    Section {
                        NavigationLink(destination: DocumentationCategoryView(category: category)) {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.name)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("\(category.files.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Documentation")
            .navigationBarTitleDisplayMode(.large)
            
            // Default content when no category is selected
            VStack(spacing: 20) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text("Select a Category")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose a documentation category from the sidebar to browse guides and technical documentation.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}

struct DocumentationCategoryView: View {
    let category: DocumentationCategory
    @State private var selectedFile: DocumentationFile?
    
    var body: some View {
        List {
            ForEach(category.files) { file in
                NavigationLink(destination: DocumentationFileView(file: file)) {
                    HStack {
                        Image(systemName: file.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.title)
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Text(file.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct DocumentationFileView: View {
    let file: DocumentationFile
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("Loading documentation...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else if hasError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Unable to Load Documentation")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("This documentation file could not be found or loaded. Please try again later.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else {
                    MarkdownView(content: content)
                        .padding()
                }
            }
        }
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        isLoading = true
        hasError = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let loadedContent = DocumentationService.shared.loadDocumentationContent(for: file) {
                DispatchQueue.main.async {
                    self.content = loadedContent
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.hasError = true
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Simple Markdown Renderer

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(parseMarkdown(content), id: \.self) { element in
                renderElement(element)
            }
        }
    }
    
    private func parseMarkdown(_ markdown: String) -> [MarkdownElement] {
        let lines = markdown.components(separatedBy: .newlines)
        var elements: [MarkdownElement] = []
        var currentCodeBlock: [String] = []
        var inCodeBlock = false
        
        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    elements.append(.codeBlock(currentCodeBlock.joined(separator: "\n")))
                    currentCodeBlock = []
                    inCodeBlock = false
                } else {
                    // Start code block
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                currentCodeBlock.append(line)
                continue
            }
            
            if line.isEmpty {
                elements.append(.spacing)
            } else if line.hasPrefix("# ") {
                elements.append(.heading1(String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                elements.append(.heading2(String(line.dropFirst(3))))
            } else if line.hasPrefix("### ") {
                elements.append(.heading3(String(line.dropFirst(4))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                elements.append(.bulletPoint(String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                elements.append(.quote(String(line.dropFirst(2))))
            } else {
                elements.append(.paragraph(line))
            }
        }
        
        return elements
    }
    
    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading1(let text):
            Text(text)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.vertical, 8)
        
        case .heading2(let text):
            Text(text)
                .font(.title)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
        
        case .heading3(let text):
            Text(text)
                .font(.title2)
                .fontWeight(.medium)
                .padding(.vertical, 4)
        
        case .paragraph(let text):
            Text(parseInlineMarkdown(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        
        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)
                    .fontWeight(.semibold)
                Text(parseInlineMarkdown(text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        
        case .quote(let text):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4)
                
                Text(parseInlineMarkdown(text))
                    .font(.body)
                    .italic()
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            .padding(.vertical, 4)
        
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        
        case .spacing:
            Spacer().frame(height: 8)
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Parse bold text (**text**)
        let boldPattern = #"\*\*(.*?)\*\*"#
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = boldRegex.matches(in: text, options: [], range: range)
            
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 0), in: text),
                   let contentRange = Range(match.range(at: 1), in: text) {
                    let content = String(text[contentRange])
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: match.range(at: 0).location)
                    let endIndex = attributedString.index(startIndex, offsetByCharacters: match.range(at: 0).length)
                    
                    var replacement = AttributedString(content)
                    replacement.font = .body.bold()
                    
                    attributedString.replaceSubrange(startIndex..<endIndex, with: replacement)
                }
            }
        }
        
        // Parse italic text (*text*)
        let italicPattern = #"(?<!\*)\*(?!\*)([^*]+)\*(?!\*)"#
        if let italicRegex = try? NSRegularExpression(pattern: italicPattern, options: []) {
            let currentText = String(attributedString.characters)
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            let matches = italicRegex.matches(in: currentText, options: [], range: range)
            
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 0), in: currentText),
                   let contentRange = Range(match.range(at: 1), in: currentText) {
                    let content = String(currentText[contentRange])
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: match.range(at: 0).location)
                    let endIndex = attributedString.index(startIndex, offsetByCharacters: match.range(at: 0).length)
                    
                    var replacement = AttributedString(content)
                    replacement.font = .body.italic()
                    
                    attributedString.replaceSubrange(startIndex..<endIndex, with: replacement)
                }
            }
        }
        
        // Parse inline code (`code`)
        let codePattern = #"`([^`]+)`"#
        if let codeRegex = try? NSRegularExpression(pattern: codePattern, options: []) {
            let currentText = String(attributedString.characters)
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            let matches = codeRegex.matches(in: currentText, options: [], range: range)
            
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 0), in: currentText),
                   let contentRange = Range(match.range(at: 1), in: currentText) {
                    let content = String(currentText[contentRange])
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: match.range(at: 0).location)
                    let endIndex = attributedString.index(startIndex, offsetByCharacters: match.range(at: 0).length)
                    
                    var replacement = AttributedString(content)
                    replacement.font = .system(.body, design: .monospaced)
                    replacement.backgroundColor = Color.secondary.opacity(0.2)
                    
                    attributedString.replaceSubrange(startIndex..<endIndex, with: replacement)
                }
            }
        }
        
        // Parse links [text](url)
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            let currentText = String(attributedString.characters)
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            let matches = linkRegex.matches(in: currentText, options: [], range: range)
            
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 0), in: currentText),
                   let textRange = Range(match.range(at: 1), in: currentText),
                   let urlRange = Range(match.range(at: 2), in: currentText) {
                    let linkText = String(currentText[textRange])
                    let linkURL = String(currentText[urlRange])
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: match.range(at: 0).location)
                    let endIndex = attributedString.index(startIndex, offsetByCharacters: match.range(at: 0).length)
                    
                    var replacement = AttributedString(linkText)
                    replacement.foregroundColor = .blue
                    replacement.underlineStyle = .single
                    if let url = URL(string: linkURL) {
                        replacement.link = url
                    }
                    
                    attributedString.replaceSubrange(startIndex..<endIndex, with: replacement)
                }
            }
        }
        
        return attributedString
    }
}

enum MarkdownElement: Hashable {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case paragraph(String)
    case bulletPoint(String)
    case quote(String)
    case codeBlock(String)
    case spacing
}

#Preview {
    DocumentationView()
} 