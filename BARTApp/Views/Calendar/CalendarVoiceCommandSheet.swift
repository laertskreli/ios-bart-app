import SwiftUI
import Speech
import AVFoundation

// MARK: - Speech Recognizer

class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthorized: Bool = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init() {
        checkAuthorization()
    }
    
    func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                case .denied, .restricted, .notDetermined:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition not authorized"
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        errorMessage = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    self?.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self?.recognitionRequest = nil
                    self?.recognitionTask = nil
                    self?.isRecording = false
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
    }
}

// MARK: - Voice Command Types

enum CalendarVoiceAction: Identifiable {
    case reschedule(eventTitle: String, newTime: String)
    case sendLateNotice(eventTitle: String, minutes: Int)
    case sendMeetingInvite(title: String, time: String, attendees: [String])
    case cancel(eventTitle: String)
    case unknown(rawCommand: String)
    
    var id: String {
        switch self {
        case .reschedule(let title, _): return "reschedule-\(title)"
        case .sendLateNotice(let title, _): return "late-\(title)"
        case .sendMeetingInvite(let title, _, _): return "invite-\(title)"
        case .cancel(let title): return "cancel-\(title)"
        case .unknown(let cmd): return "unknown-\(cmd)"
        }
    }
}

// MARK: - Voice Command Parser

struct VoiceCommandParser {
    static func parse(_ text: String) -> CalendarVoiceAction {
        let lowercased = text.lowercased()
        
        if lowercased.contains("move") || lowercased.contains("reschedule") {
            let timePattern = try? NSRegularExpression(pattern: "(\\d{1,2}\\s*(?:am|pm|AM|PM)?)", options: [])
            let range = NSRange(lowercased.startIndex..., in: lowercased)
            let matches = timePattern?.matches(in: lowercased, options: [], range: range) ?? []
            
            var times: [String] = []
            for match in matches {
                if let r = Range(match.range, in: lowercased) {
                    times.append(String(lowercased[r]))
                }
            }
            
            let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tomorrow", "today"]
            var targetDay = ""
            for day in days {
                if lowercased.contains(day) {
                    targetDay = day.capitalized
                    break
                }
            }
            
            if let firstTime = times.first {
                let newTime = targetDay.isEmpty ? (times.count > 1 ? times[1] : "later") : "\(targetDay) \(times.last ?? "")"
                return .reschedule(eventTitle: "\(firstTime) meeting", newTime: newTime.trimmingCharacters(in: .whitespaces))
            }
        }
        
        if lowercased.contains("late") && (lowercased.contains("tell") || lowercased.contains("let") || lowercased.contains("notify")) {
            let timePattern = try? NSRegularExpression(pattern: "(\\d{1,2}\\s*(?:am|pm)?)", options: [])
            let range = NSRange(lowercased.startIndex..., in: lowercased)
            if let match = timePattern?.firstMatch(in: lowercased, options: [], range: range),
               let r = Range(match.range, in: lowercased) {
                let eventTime = String(lowercased[r])
                
                let minutesPattern = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:min|minute)", options: [])
                var minutes = 5
                if let minMatch = minutesPattern?.firstMatch(in: lowercased, options: [], range: range),
                   let minRange = Range(minMatch.range(at: 1), in: lowercased) {
                    minutes = Int(lowercased[minRange]) ?? 5
                }
                
                return .sendLateNotice(eventTitle: "\(eventTime) meeting", minutes: minutes)
            }
        }
        
        if lowercased.contains("cancel") {
            let timePattern = try? NSRegularExpression(pattern: "(\\d{1,2}\\s*(?:am|pm)?)", options: [])
            let range = NSRange(lowercased.startIndex..., in: lowercased)
            if let match = timePattern?.firstMatch(in: lowercased, options: [], range: range),
               let r = Range(match.range, in: lowercased) {
                let eventTime = String(lowercased[r])
                return .cancel(eventTitle: "\(eventTime) meeting")
            }
        }
        
        return .unknown(rawCommand: text)
    }
}

// MARK: - Voice Command Sheet

struct CalendarVoiceCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var parsedAction: CalendarVoiceAction?
    @State private var pulseAnimation = false
    
    var onActionConfirmed: ((CalendarVoiceAction) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    ZStack {
                        if speechRecognizer.isRecording {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .stroke(Color.accentColor.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                                    .frame(width: 120 + CGFloat(i) * 30, height: 120 + CGFloat(i) * 30)
                                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                    .opacity(pulseAnimation ? 0 : 1)
                                    .animation(
                                        .easeOut(duration: 1.5)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.3),
                                        value: pulseAnimation
                                    )
                            }
                        }
                        
                        Button {
                            toggleRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(speechRecognizer.isRecording ? Color.red : Color.accentColor)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: (speechRecognizer.isRecording ? Color.red : Color.accentColor).opacity(0.5), radius: 20)
                                
                                Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white)
                            }
                        }
                        .disabled(!speechRecognizer.isAuthorized)
                    }
                    
                    VStack(spacing: 8) {
                        if !speechRecognizer.isAuthorized {
                            Text("Microphone access required")
                                .font(.headline)
                                .foregroundStyle(.red)
                        } else if speechRecognizer.isRecording {
                            Text("Listening...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        } else {
                            Text("Tap to speak a command")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        
                        Text("Try: \"Move my 2pm to Friday\" or \"Tell my 3pm I'm 5 minutes late\"")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    if !speechRecognizer.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You said:")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            
                            Text(speechRecognizer.transcript)
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(white: 0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                    
                    if let action = parsedAction {
                        VoiceActionCard(action: action) {
                            onActionConfirmed?(action)
                            dismiss()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Voice Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speechRecognizer.stopRecording()
                        dismiss()
                    }
                }
            }
            .onChange(of: speechRecognizer.transcript) { _, newValue in
                if !newValue.isEmpty && !speechRecognizer.isRecording {
                    withAnimation(.spring(response: 0.3)) {
                        parsedAction = VoiceCommandParser.parse(newValue)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            pulseAnimation = false
        } else {
            parsedAction = nil
            do {
                try speechRecognizer.startRecording()
                pulseAnimation = true
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
}

// MARK: - Voice Action Card

struct VoiceActionCard: View {
    let action: CalendarVoiceAction
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                
                Text(actionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            Text(actionDescription)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                onConfirm()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirm")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(iconColor.opacity(0.3), lineWidth: 1)
        }
        .padding(.horizontal)
    }
    
    private var iconName: String {
        switch action {
        case .reschedule: return "calendar.badge.clock"
        case .sendLateNotice: return "clock.badge.exclamationmark"
        case .sendMeetingInvite: return "envelope.badge.person.crop"
        case .cancel: return "calendar.badge.minus"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch action {
        case .reschedule: return .blue
        case .sendLateNotice: return .orange
        case .sendMeetingInvite: return .green
        case .cancel: return .red
        case .unknown: return .gray
        }
    }
    
    private var actionTitle: String {
        switch action {
        case .reschedule: return "Reschedule Event"
        case .sendLateNotice: return "Send Late Notice"
        case .sendMeetingInvite: return "Send Meeting Invite"
        case .cancel: return "Cancel Event"
        case .unknown: return "Unknown Command"
        }
    }
    
    private var actionDescription: String {
        switch action {
        case .reschedule(let title, let newTime):
            return "Move \"\(title)\" to \(newTime)"
        case .sendLateNotice(let title, let minutes):
            return "Notify attendees of \"\(title)\" that you\'ll be \(minutes) minutes late"
        case .sendMeetingInvite(let title, let time, let attendees):
            return "Create \"\(title)\" at \(time) with \(attendees.joined(separator: ", "))"
        case .cancel(let title):
            return "Cancel \"\(title)\" and notify attendees"
        case .unknown(let cmd):
            return "Could not understand: \"\(cmd)\""
        }
    }
}


#Preview {
    CalendarVoiceCommandSheet()
}
