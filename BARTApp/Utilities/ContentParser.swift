import Foundation

struct ContentParser {

    // MARK: - Cache

    /// Cache for parsed content to avoid re-parsing on every view render
    private static var cache = ParsedContentCache()

    private class ParsedContentCache {
        private var storage: [Int: (content: String, blocks: [ParsedContentBlock])] = [:]
        private let maxSize = 100
        private var accessOrder: [Int] = []

        func get(_ content: String) -> [ParsedContentBlock]? {
            let key = content.hashValue
            guard let cached = storage[key], cached.content == content else {
                return nil
            }
            // Move to end of access order (most recently used)
            if let idx = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: idx)
                accessOrder.append(key)
            }
            return cached.blocks
        }

        func set(_ content: String, blocks: [ParsedContentBlock]) {
            let key = content.hashValue

            // Evict oldest if at capacity
            if storage.count >= maxSize, let oldest = accessOrder.first {
                storage.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }

            storage[key] = (content, blocks)
            accessOrder.append(key)
        }

        func clear() {
            storage.removeAll()
            accessOrder.removeAll()
        }
    }

    /// Clear the parse cache (useful after clearing history)
    static func clearCache() {
        cache.clear()
    }

    // MARK: - Code Block Extraction

    /// Extracts JSON from markdown code blocks (```json ... ```)
    /// If the entire content is wrapped in a code block, returns just the JSON
    private static func extractJSONFromCodeBlocks(_ content: String) -> String {
        // Pattern to match ```json ... ``` or ``` ... ```
        let codeBlockPattern = #"```(?:json)?\s*([\s\S]*?)```"#

        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else {
            return content
        }

        var result = content
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        // Replace code blocks with their contents
        let matches = regex.matches(in: content, options: [], range: range)

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            guard let innerRange = Range(match.range(at: 1), in: content),
                  let fullRange = Range(match.range, in: content) else { continue }

            let innerContent = String(content[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Only replace if the inner content looks like JSON (starts with {)
            if innerContent.hasPrefix("{") {
                result.replaceSubrange(fullRange, with: innerContent)
            }
        }

        return result
    }

    /// Maximum content length to parse (avoid parsing huge content)
    private static let maxContentLength = 50_000
    /// Maximum number of JSON blocks to extract per message
    private static let maxJsonBlocks = 10

    /// Parses message content into blocks of text and interactive components
    static func parse(_ content: String) -> [ParsedContentBlock] {
        // Check cache first
        if let cached = cache.get(content) {
            return cached
        }

        // Safety: skip very large content
        guard content.count < maxContentLength else {
            print("[ContentParser] Content too large (\(content.count) chars), returning as text")
            let result = [ParsedContentBlock.text(content)]
            cache.set(content, blocks: result)
            return result
        }

        print("[ContentParser] Parsing content: \(content.prefix(200))...")

        // First, extract JSON from markdown code blocks if present
        let processedContent = extractJSONFromCodeBlocks(content)

        var blocks: [ParsedContentBlock] = []
        var searchRange = processedContent.startIndex..<processedContent.endIndex
        var jsonBlockCount = 0

        while let openBrace = processedContent.range(of: "{", range: searchRange) {
            // Safety: limit number of JSON blocks
            guard jsonBlockCount < maxJsonBlocks else {
                let remaining = String(processedContent[searchRange])
                if !remaining.isEmpty {
                    blocks.append(.text(remaining))
                }
                break
            }
            // Add any text before this potential JSON block
            let textBefore = String(processedContent[searchRange.lowerBound..<openBrace.lowerBound])
            if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(textBefore))
            }

            // Try to find matching closing brace
            if let jsonRange = findJSONBlock(in: processedContent, startingAt: openBrace.lowerBound) {
                let jsonString = String(processedContent[jsonRange])
                jsonBlockCount += 1

                // Try to parse as interactive component
                if let component = parseInteractiveComponent(jsonString) {
                    blocks.append(component)
                } else {
                    // Not a valid interactive component, treat as text
                    blocks.append(.text(jsonString))
                }

                searchRange = jsonRange.upperBound..<processedContent.endIndex
            } else {
                // No matching closing brace, treat rest as text
                let remaining = String(processedContent[openBrace.lowerBound..<processedContent.endIndex])
                blocks.append(.text(remaining))
                break
            }
        }

        // Add any remaining text after last JSON block
        if searchRange.lowerBound < processedContent.endIndex {
            let remaining = String(processedContent[searchRange])
            if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(remaining))
            }
        }

        // If no blocks found, return the entire content as text
        let result = blocks.isEmpty ? [.text(processedContent)] : blocks
        print("[ContentParser] Parsed \(result.count) blocks: \(result.map { block in switch block { case .text: return "text" case .button: return "button" case .buttonGroup: return "buttonGroup" case .calendar: return "calendar" case .calendarSchedule: return "calendarSchedule" case .emailDraft: return "emailDraft" case .options: return "options" case .tasks: return "tasks" case .form: return "form" case .code: return "code" case .linkPreview: return "linkPreview" case .file: return "file" case .contact: return "contact" case .chart: return "chart" case .location: return "location" case .resolved: return "resolved" }})")

        // Cache the result
        cache.set(content, blocks: result)

        return result
    }

    /// Maximum characters to scan for a single JSON block
    private static let maxJsonBlockLength = 10_000

    /// Finds a balanced JSON object starting at the given index
    private static func findJSONBlock(in content: String, startingAt start: String.Index) -> Range<String.Index>? {
        guard content[start] == "{" else { return nil }

        var depth = 0
        var inString = false
        var escapeNext = false
        var index = start
        var charCount = 0

        while index < content.endIndex {
            // Safety: limit scan length
            charCount += 1
            if charCount > maxJsonBlockLength {
                return nil
            }

            let char = content[index]

            if escapeNext {
                escapeNext = false
            } else if char == "\\" && inString {
                escapeNext = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let endIndex = content.index(after: index)
                        return start..<endIndex
                    }
                }
            }

            index = content.index(after: index)
        }

        return nil
    }

    /// Attempts to parse a JSON string as an interactive component
    private static func parseInteractiveComponent(_ json: String) -> ParsedContentBlock? {
        guard let data = json.data(using: .utf8) else {
            print("[ContentParser] Failed to convert JSON to data: \(json.prefix(100))")
            return nil
        }

        // Try to parse as dictionary for flexible resolution
        guard let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ContentParser] Failed to parse as dictionary: \(json.prefix(100))")
            return nil
        }

        // First, try the flexible ContentResolver
        if let resolved = ContentResolver.resolve(jsonDict) {
            print("[ContentParser] Resolved via flexible resolver")
            return .resolved(resolved)
        }

        // Fall back to strict schema parsing
        struct TypeWrapper: Decodable {
            let type: String
        }

        guard let wrapper = try? JSONDecoder().decode(TypeWrapper.self, from: data) else {
            print("[ContentParser] No 'type' field found in JSON: \(json.prefix(100))")
            return nil
        }

        print("[ContentParser] Found component type: \(wrapper.type), trying strict parsing")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch wrapper.type {
        case "button":
            do {
                let component = try decoder.decode(ButtonComponent.self, from: data)
                print("[ContentParser] Successfully parsed button: \(component.id)")
                return .button(component)
            } catch {
                print("[ContentParser] Failed to parse button: \(error)")
                return nil
            }

        case "buttonGroup":
            do {
                let component = try decoder.decode(ButtonGroupComponent.self, from: data)
                print("[ContentParser] Successfully parsed buttonGroup: \(component.id)")
                return .buttonGroup(component)
            } catch {
                print("[ContentParser] Failed to parse buttonGroup: \(error)")
                return nil
            }

        case "calendar":
            // Check if it's a schedule (has events array) or single event (has startDate)
            struct CalendarTypeChecker: Decodable {
                let events: [CalendarScheduleComponent.ScheduleEvent]?
                let startDate: Date?
            }
            if let checker = try? decoder.decode(CalendarTypeChecker.self, from: data),
               checker.events != nil {
                // It's a schedule/agenda
                do {
                    let component = try decoder.decode(CalendarScheduleComponent.self, from: data)
                    print("[ContentParser] Successfully parsed calendar schedule: \(component.id)")
                    return .calendarSchedule(component)
                } catch {
                    print("[ContentParser] Failed to parse calendar schedule: \(error)")
                    return nil
                }
            } else {
                // It's a single event
                do {
                    let component = try decoder.decode(CalendarComponent.self, from: data)
                    print("[ContentParser] Successfully parsed calendar event: \(component.id)")
                    return .calendar(component)
                } catch {
                    print("[ContentParser] Failed to parse calendar event: \(error)")
                    return nil
                }
            }

        case "emailDraft":
            do {
                let component = try decoder.decode(EmailDraftComponent.self, from: data)
                print("[ContentParser] Successfully parsed emailDraft: \(component.id)")
                return .emailDraft(component)
            } catch {
                print("[ContentParser] Failed to parse emailDraft: \(error)")
                return nil
            }

        case "options":
            do {
                let component = try decoder.decode(OptionsComponent.self, from: data)
                print("[ContentParser] Successfully parsed options: \(component.id)")
                return .options(component)
            } catch {
                print("[ContentParser] Failed to parse options: \(error)")
                return nil
            }

        case "tasks":
            do {
                let component = try decoder.decode(TasksComponent.self, from: data)
                print("[ContentParser] Successfully parsed tasks: \(component.id)")
                return .tasks(component)
            } catch {
                print("[ContentParser] Failed to parse tasks: \(error)")
                return nil
            }

        case "form":
            do {
                let component = try decoder.decode(FormComponent.self, from: data)
                print("[ContentParser] Successfully parsed form: \(component.id)")
                return .form(component)
            } catch {
                print("[ContentParser] Failed to parse form: \(error)")
                return nil
            }

        case "code":
            do {
                let component = try decoder.decode(CodeComponent.self, from: data)
                print("[ContentParser] Successfully parsed code: \(component.id)")
                return .code(component)
            } catch {
                print("[ContentParser] Failed to parse code: \(error)")
                return nil
            }

        case "linkPreview":
            do {
                let component = try decoder.decode(LinkPreviewComponent.self, from: data)
                print("[ContentParser] Successfully parsed linkPreview: \(component.id)")
                return .linkPreview(component)
            } catch {
                print("[ContentParser] Failed to parse linkPreview: \(error)")
                return nil
            }

        case "file":
            do {
                let component = try decoder.decode(FileComponent.self, from: data)
                print("[ContentParser] Successfully parsed file: \(component.id)")
                return .file(component)
            } catch {
                print("[ContentParser] Failed to parse file: \(error)")
                return nil
            }

        case "contact":
            do {
                let component = try decoder.decode(ContactComponent.self, from: data)
                print("[ContentParser] Successfully parsed contact: \(component.id)")
                return .contact(component)
            } catch {
                print("[ContentParser] Failed to parse contact: \(error)")
                return nil
            }

        case "chart":
            do {
                let component = try decoder.decode(ChartComponent.self, from: data)
                print("[ContentParser] Successfully parsed chart: \(component.id)")
                return .chart(component)
            } catch {
                print("[ContentParser] Failed to parse chart: \(error)")
                return nil
            }

        case "location":
            do {
                let component = try decoder.decode(LocationComponent.self, from: data)
                print("[ContentParser] Successfully parsed location: \(component.id)")
                return .location(component)
            } catch {
                print("[ContentParser] Failed to parse location: \(error)")
                return nil
            }

        default:
            print("[ContentParser] Unknown component type: \(wrapper.type)")
            return nil
        }
    }
}
