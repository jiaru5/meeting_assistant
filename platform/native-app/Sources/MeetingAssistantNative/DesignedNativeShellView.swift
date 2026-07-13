import AppKit
import SwiftUI

public enum MeetingTaskAccessibilityID {
    public static let navigation = "ma.shell.navigation"
    public static let routeStatus = "ma.shell.selectedSection"
    public static let meetingsNavigation = "ma.navigation.meetings"
    public static let newRecordingNavigation = "ma.navigation.newRecording"
    public static let currentMeetingNavigation = "ma.navigation.currentMeeting"
    public static let diagnosticsNavigation = "ma.navigation.diagnostics"
    public static let meetingsHeading = "ma.meetings.heading"
    public static let meetingsEmpty = "ma.meetings.empty"
    public static let newRecordingButton = "ma.meetings.newRecordingButton"
    public static let recentMeetings = "ma.meetings.recent"
    public static let workspaceNotice = "ma.meetings.notice"
    public static let newRecordingHeading = "ma.newRecording.heading"
    public static let titleField = "ma.newRecording.titleField"
    public static let target = "ma.newRecording.target.screen"
    public static let systemAudioToggle = "ma.newRecording.systemAudio"
    public static let microphoneToggle = "ma.newRecording.microphone"
    public static let readiness = "ma.newRecording.readiness"
    public static let checkAgain = "ma.newRecording.checkAgain"
    public static let detailHeading = "ma.meetingDetail.heading"
    public static let detailStatus = "ma.meetingDetail.status"
    public static let recordingTimer = "ma.meetingDetail.recordingTimer"
    public static let audioSummary = "ma.meetingDetail.audioSummary"
    public static let savedSummary = "ma.meetingDetail.savedSummary"
    public static let transcriptLoadError = "ma.meetingDetail.transcriptLoadError"
    public static let reloadTranscript = "ma.meetingDetail.reloadTranscript"
    public static let recoveryStatus = "ma.meetingDetail.recoveryStatus"
    public static let startNewRecording = "ma.meetingDetail.startNewRecording"
    public static let technicalDetails = "ma.meetingDetail.technicalDetails"
    public static let chooseMeeting = "ma.meetingDetail.chooseMeeting"
    public static let diagnosticsHeading = "ma.diagnostics.heading"
    public static let workspacePath = "ma.diagnostics.workspacePath"

    public static func meetingRow(_ sessionID: String) -> String {
        "ma.meetings.row.\(sessionID)"
    }
}

func meetingTimestampDate(_ timestamp: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp)
}

func meetingFriendlyDate(_ timestamp: String) -> String {
    guard let date = meetingTimestampDate(timestamp) else {
        return "Meeting date unavailable"
    }
    return date.formatted(date: .abbreviated, time: .shortened)
}

func recordingArtifactIsUsable(_ artifact: RecordingCommandArtifact) -> Bool {
    (artifact.captureStatus == "available" || artifact.captureStatus == "degraded")
        && artifact.path?.isEmpty == false
        && artifact.checksum?.isEmpty == false
}

func recordingArtifactWasNotRequested(_ artifact: RecordingCommandArtifact) -> Bool {
    guard artifact.captureStatus == "missing",
          let reason = artifact.degradationReason else {
        return false
    }
    return reason.localizedCaseInsensitiveContains(
        "was not requested for this native capture session"
    )
}

func recordingSavedArtifactSummary(
    artifacts: [RecordingCommandArtifact],
    fallbackCount: Int
) -> String {
    guard !artifacts.isEmpty else {
        return fallbackCount == 1
            ? "1 meeting file is available."
            : "\(fallbackCount) meeting files are available."
    }

    let requestedArtifacts = artifacts.filter { !recordingArtifactWasNotRequested($0) }
    let successful = requestedArtifacts.filter(recordingArtifactIsUsable).count
    let unavailable = requestedArtifacts.count - successful
    let hasUnrequestedAudio = requestedArtifacts.count != artifacts.count

    let readinessSummary: String
    if unavailable > 0 {
        let readyFiles = successful == 1
            ? "1 meeting file is ready"
            : "\(successful) meeting files are ready"
        let unavailableSources = unavailable == 1
            ? "1 requested source was unavailable"
            : "\(unavailable) requested sources were unavailable"
        readinessSummary = "\(readyFiles); \(unavailableSources). Successful files were kept."
    } else {
        readinessSummary = successful == 1
            ? "1 meeting file is ready."
            : "\(successful) meeting files are ready."
    }

    if hasUnrequestedAudio {
        return "\(readinessSummary) Optional audio was left out as requested."
    }
    return readinessSummary
}

func recordingArtifactDisplayName(_ artifactType: String) -> String {
    switch artifactType {
    case "screen_video":
        return "Screen recording"
    case "system_audio":
        return "System audio"
    case "microphone_audio":
        return "Microphone"
    case "mixed_audio":
        return "Meeting audio"
    default:
        return "Meeting file"
    }
}

func recordingArtifactUserStatus(_ artifact: RecordingCommandArtifact) -> String {
    if recordingArtifactWasNotRequested(artifact) {
        return "Not requested."
    }
    if recordingArtifactIsUsable(artifact) {
        return artifact.captureStatus == "degraded" ? "Saved with limited quality." : "Ready."
    }

    let fallback = "This source was not saved."
    let reason = artifact.degradationReason?.processingSafeDisplayText(fallback: fallback) ?? fallback
    let rawContractMarkers = ["artifact_type", "artifact-type", "capture_status", "capture-status"]
    let containsRawType = artifact.artifactType.contains("_")
        && reason.localizedCaseInsensitiveContains(artifact.artifactType)
    let containsRawContractMarker = rawContractMarkers.contains {
        reason.localizedCaseInsensitiveContains($0)
    }
    let isRawStatusOnly = reason.caseInsensitiveCompare(artifact.captureStatus) == .orderedSame
    let userReason = containsRawType || containsRawContractMarker || isRawStatusOnly ? fallback : reason
    switch artifact.captureStatus {
    case "missing":
        return "Not captured. \(userReason)"
    case "failed":
        return "Could not be saved. \(userReason)"
    case "degraded":
        return "Unavailable. \(userReason)"
    default:
        return userReason
    }
}

func recordingArtifactAccessibilityLabel(_ artifact: RecordingCommandArtifact) -> String {
    "\(recordingArtifactDisplayName(artifact.artifactType)), \(recordingArtifactUserStatus(artifact))"
}

func historicalMeetingRecoveryStatus(_ status: String) -> String? {
    switch status {
    case "created":
        return "Recording not started"
    case "recording":
        return "Recording interrupted"
    case "processing":
        return "Transcript interrupted"
    case "failed":
        return "Needs attention"
    case "recorded", "transcribed":
        return nil
    default:
        return "Needs attention"
    }
}

func meetingUserStatus(_ status: String, hasTranscript: Bool) -> String {
    if let recoveryStatus = historicalMeetingRecoveryStatus(status) {
        return recoveryStatus
    }
    if hasTranscript {
        return "Transcript ready"
    }
    switch status {
    case "transcribed":
        return "Transcript unavailable"
    case "recorded":
        return "Ready to transcribe"
    default:
        return "Needs attention"
    }
}

public struct DesignedNativeShellView: View {
    @ObservedObject private var coordinator: MeetingWorkspaceCoordinator
    @ObservedObject private var permissionViewModel: PermissionDependencyStatusViewModel
    @ObservedObject private var recordingViewModel: RecordingControlViewModel
    @ObservedObject private var processingViewModel: ProcessingStateViewModel
    @ObservedObject private var transcriptActionViewModel: TranscriptReviewActionsViewModel
    private let transcriptViewModel: TranscriptReviewViewModel
    private let autoRefreshPreflightOnAppear: Bool
    private let startRecording: (MeetingRecordingDraft) -> Void
    private let stopRecording: () -> Void
    private let startProcessing: () -> Void
    private let retryProcessing: () -> Void
    private let openMeeting: (MeetingSessionSummary) -> Void
    private let reloadTranscript: () -> Void
    private let confirmDelete: () -> Void
    @State private var didAutoRefreshPreflight = false
    @State private var showTechnicalDetails = false

    public init(
        coordinator: MeetingWorkspaceCoordinator,
        permissionViewModel: PermissionDependencyStatusViewModel,
        recordingViewModel: RecordingControlViewModel,
        processingViewModel: ProcessingStateViewModel,
        transcriptViewModel: TranscriptReviewViewModel,
        transcriptActionViewModel: TranscriptReviewActionsViewModel,
        autoRefreshPreflightOnAppear: Bool = false,
        startRecording: @escaping (MeetingRecordingDraft) -> Void = { _ in },
        stopRecording: @escaping () -> Void = {},
        startProcessing: @escaping () -> Void = {},
        retryProcessing: @escaping () -> Void = {},
        openMeeting: @escaping (MeetingSessionSummary) -> Void = { _ in },
        reloadTranscript: @escaping () -> Void = {},
        confirmDelete: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.permissionViewModel = permissionViewModel
        self.recordingViewModel = recordingViewModel
        self.processingViewModel = processingViewModel
        self.transcriptViewModel = transcriptViewModel
        self.transcriptActionViewModel = transcriptActionViewModel
        self.autoRefreshPreflightOnAppear = autoRefreshPreflightOnAppear
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.startProcessing = startProcessing
        self.retryProcessing = retryProcessing
        self.openMeeting = openMeeting
        self.reloadTranscript = reloadTranscript
        self.confirmDelete = confirmDelete
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 244)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                routeContent
                    .padding(.horizontal, 44)
                    .padding(.vertical, 34)
                    .frame(maxWidth: 960, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 980, minHeight: 680)
        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.root)
        .onChange(of: permissionViewModel.state) { _, readiness in
            recordingViewModel.updateReadiness(readiness)
            processingViewModel.updateReadiness(readiness)
        }
        .task {
            coordinator.refreshSessions()
            await autoRefreshPreflightIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text("Meeting Assistant")
                        .font(.headline)
                }
                Text("Local meeting capture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                navigationButton(
                    title: "Meetings",
                    systemImage: "rectangle.stack",
                    route: .meetings,
                    identifier: MeetingTaskAccessibilityID.meetingsNavigation
                )
                navigationButton(
                    title: "New recording",
                    systemImage: "record.circle",
                    route: .newRecording,
                    identifier: MeetingTaskAccessibilityID.newRecordingNavigation
                )

                if coordinator.currentSession != nil {
                    navigationButton(
                        title: coordinator.currentMeetingTitle,
                        systemImage: "doc.text",
                        route: .meetingDetail,
                        identifier: MeetingTaskAccessibilityID.currentMeetingNavigation
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Main navigation")
            .accessibilityIdentifier(MeetingTaskAccessibilityID.navigation)

            Spacer()

            navigationButton(
                title: "Settings & diagnostics",
                systemImage: "gearshape",
                route: .diagnostics,
                identifier: MeetingTaskAccessibilityID.diagnosticsNavigation
            )

            Label("Stored only on this Mac", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting Assistant navigation")
    }

    private func navigationButton(
        title: String,
        systemImage: String,
        route: MeetingWorkspaceRoute,
        identifier: String
    ) -> some View {
        Button {
            if route == .newRecording {
                coordinator.beginNewRecording()
            } else {
                coordinator.navigate(to: route)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(coordinator.route == route ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(coordinator.navigationIsLocked && coordinator.route != route)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var routeContent: some View {
        switch coordinator.route {
        case .meetings:
            meetingsView
        case .newRecording:
            newRecordingView
        case .meetingDetail:
            meetingDetailView
        case .diagnostics:
            diagnosticsView
        }
    }

    private var meetingsView: some View {
        VStack(alignment: .leading, spacing: 26) {
            pageHeader(
                eyebrow: "YOUR WORKSPACE",
                title: "Meetings",
                subtitle: "Record a conversation, create a transcript, or continue where you left off.",
                identifier: MeetingTaskAccessibilityID.meetingsHeading
            )

            if let notice = coordinator.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.workspaceNotice)
            }

            if let workspaceError = coordinator.workspaceError {
                recoveryCard(
                    title: "Your meetings could not be loaded",
                    message: "Nothing was changed. Open Diagnostics to check the local workspace, then try again. \(workspaceError)",
                    actionTitle: "Open diagnostics",
                    action: { coordinator.navigate(to: .diagnostics) }
                )
            }

            if coordinator.recentSessions.isEmpty {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 70, height: 70)
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.tint)
                    }

                    VStack(spacing: 7) {
                        Text("Record your first meeting")
                            .font(.title2.weight(.semibold))
                        Text("Capture your screen and meeting audio, then create a local transcript when you are ready.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 470)
                    }

                    Button("New recording") {
                        coordinator.beginNewRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.newRecordingButton)
                }
                .padding(.vertical, 58)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .cardStyle()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(MeetingTaskAccessibilityID.meetingsEmpty)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent meetings")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button("New recording") {
                            coordinator.beginNewRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.newRecordingButton)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(coordinator.recentSessions.enumerated()), id: \.element.id) { index, meeting in
                            meetingRow(meeting)
                            if index < coordinator.recentSessions.count - 1 {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .cardStyle(padding: 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.recentMeetings)
                }
            }

            if !coordinator.workspaceIssues.isEmpty {
                Label(
                    "\(coordinator.workspaceIssues.count) damaged meeting could not be shown. Your other meetings are unchanged; see Diagnostics for details.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func meetingRow(_ meeting: MeetingSessionSummary) -> some View {
        Button {
            openMeeting(meeting)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(statusColor(meeting.status, hasTranscript: meeting.hasTranscript).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: meeting.hasTranscript ? "doc.text" : "waveform")
                        .foregroundStyle(statusColor(meeting.status, hasTranscript: meeting.hasTranscript))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(meeting))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(meetingMetadata(meeting))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(meetingUserStatus(meeting.status, hasTranscript: meeting.hasTranscript))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor(meeting.status, hasTranscript: meeting.hasTranscript))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            statusColor(meeting.status, hasTranscript: meeting.hasTranscript).opacity(0.1)
                        )
                    )

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayTitle(meeting)), \(meetingUserStatus(meeting.status, hasTranscript: meeting.hasTranscript)), \(meetingMetadata(meeting))")
        .accessibilityIdentifier(MeetingTaskAccessibilityID.meetingRow(meeting.id))
    }

    private var newRecordingView: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "NEW MEETING",
                title: "Set up your recording",
                subtitle: "Choose what to capture. You can create the transcript after the recording is safely saved.",
                identifier: MeetingTaskAccessibilityID.newRecordingHeading
            )

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Meeting title")
                        .font(.headline)
                    TextField("Optional — for example, Weekly planning", text: $coordinator.recordingDraft.title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Meeting title")
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.titleField)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Record")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Image(systemName: "display")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Entire screen")
                                .font(.body.weight(.medium))
                            Text("The currently supported recording target")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.target)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio")
                        .font(.headline)
                    Toggle("System audio", isOn: $coordinator.recordingDraft.captureSystemAudio)
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.systemAudioToggle)
                    Toggle("Microphone", isOn: $coordinator.recordingDraft.captureMicrophoneAudio)
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.microphoneToggle)
                }
            }
            .cardStyle()
            .disabled(coordinator.navigationIsLocked)

            readinessCard

            if recordingViewModel.state.phase == .failed,
               recordingViewModel.state.sessionID == nil {
                failureSummaryCard(
                    title: "Recording did not start",
                    message: "No meeting was recorded. Your settings are unchanged, so you can check permissions and try again. \(recordingViewModel.state.errorMessage ?? "")"
                )
            }

            HStack {
                Button("Back") {
                    coordinator.navigate(to: .meetings)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.navigationIsLocked)

                Spacer()

                Button(recordingViewModel.state.phase == .failed ? "Try recording again" : "Start recording") {
                    startRecording(coordinator.recordingDraft)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!recordingViewModel.canStart)
                .keyboardShortcut("r", modifiers: [.command, .option])
                .accessibilityIdentifier(RecordingControlAccessibilityID.startButton)
            }
        }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: readinessIcon)
                .font(.title3)
                .foregroundStyle(readinessColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(readinessTitle)
                    .font(.headline)
                Text(readinessMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if permissionViewModel.state.phase != .ready {
                Button("Check again") {
                    Task {
                        await permissionViewModel.refresh(workspaceURL: coordinator.workspaceURL)
                    }
                }
                .disabled(permissionViewModel.state.phase == .checking)
                .accessibilityIdentifier(MeetingTaskAccessibilityID.checkAgain)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MeetingTaskAccessibilityID.readiness)
    }

    @ViewBuilder
    private var meetingDetailView: some View {
        if coordinator.currentSession == nil {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    eyebrow: "MEETING",
                    title: "Choose a meeting",
                    subtitle: "Open a recent meeting or start a new recording.",
                    identifier: MeetingTaskAccessibilityID.detailHeading
                )
                Button("Choose meeting") {
                    coordinator.navigate(to: .meetings)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(MeetingTaskAccessibilityID.chooseMeeting)
            }
        } else if recordingViewModel.state.phase == .starting
                    || recordingViewModel.state.phase == .recording
                    || recordingViewModel.state.phase == .stopping {
            focusedRecordingView
        } else if recordingViewModel.state.phase == .failed,
                  recordingViewModel.state.sessionID != nil {
            recordingSaveFailureView
        } else if processingViewModel.state.isBusy {
            processingView
        } else if processingViewModel.state.phase == .failed {
            processingFailureView
        } else if let sessionStatus = coordinator.currentSession?.status,
                  historicalMeetingRecoveryStatus(sessionStatus) != nil {
            historicalMeetingRecoveryView(status: sessionStatus)
        } else if let transcriptLoadError = coordinator.transcriptLoadError {
            transcriptLoadFailureView(transcriptLoadError)
        } else if transcriptViewModel.state.contentState != .missing,
                  coordinator.currentSession?.hasTranscript == true
                    || processingViewModel.state.phase == .completed
                    || processingViewModel.state.phase == .degraded {
            transcriptResultView
        } else {
            savedMeetingView
        }
    }

    private var focusedRecordingView: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Label("Recording", systemImage: "record.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.detailStatus)
                Spacer()
                Text("Stored locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text(coordinator.currentMeetingTitle)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.detailHeading)

                if recordingViewModel.state.phase == .recording {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedRecordingTime(at: context.date))
                            .font(.system(size: 48, weight: .light, design: .monospaced))
                            .contentTransition(.numericText())
                            .accessibilityLabel("Recorded for \(elapsedRecordingTime(at: context.date))")
                            .accessibilityIdentifier(MeetingTaskAccessibilityID.recordingTimer)
                    }
                } else {
                    Text(recordingViewModel.state.phase == .stopping ? "Saving…" : "Starting…")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.recordingTimer)
                }

                Text(recordingAudioSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.audioSummary)
            }
            .padding(.vertical, 52)
            .frame(maxWidth: .infinity)

            Button(recordingViewModel.state.phase == .stopping ? "Saving recording…" : "Stop recording") {
                stopRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!recordingViewModel.canStop)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .accessibilityIdentifier(RecordingControlAccessibilityID.stopButton)

            Text("Stopping saves the recording before any transcript is created.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var recordingSaveFailureView: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "SAVE NEEDS ATTENTION",
                title: coordinator.currentMeetingTitle,
                subtitle: "The recording session is still selected. Meeting Assistant has not switched to another meeting.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )
            recoveryCard(
                title: "The recording could not be saved",
                message: "The current session is still available for another stop attempt. \(recordingViewModel.state.errorMessage ?? "")",
                actionTitle: "Try saving again",
                action: stopRecording,
                actionIdentifier: RecordingControlAccessibilityID.stopButton
            )
        }
    }

    private var savedMeetingView: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "SAVED",
                title: coordinator.currentMeetingTitle,
                subtitle: "Your recording is stored on this Mac. Create a transcript whenever you are ready.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording saved")
                            .font(.headline)
                        Text(savedArtifactSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(MeetingTaskAccessibilityID.savedSummary)
                    }
                }

                if !recordingViewModel.state.artifacts.isEmpty {
                    Divider()
                    ForEach(recordingViewModel.state.artifacts) { artifact in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: artifactStatusIcon(artifact))
                                .foregroundStyle(artifactStatusColor(artifact))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recordingArtifactDisplayName(artifact.artifactType))
                                    .font(.callout.weight(.medium))
                                Text(recordingArtifactUserStatus(artifact))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(recordingArtifactAccessibilityLabel(artifact))
                        .accessibilityIdentifier(
                            RecordingControlAccessibilityID.artifactStatus(artifact.artifactType)
                        )
                    }
                }
            }
            .cardStyle()

            if currentSessionHasProcessableAudio,
               processingViewModel.state.phase == .blocked {
                recoveryCard(
                    title: "Transcript setup needs attention",
                    message: "\(processingViewModel.state.statusText) Your recording is safe. Review the missing permission or local tool, then return to this meeting.",
                    actionTitle: "Open diagnostics",
                    action: { coordinator.navigate(to: .diagnostics) }
                )
            } else if currentSessionHasProcessableAudio {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Next step")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Create a timestamped transcript")
                        .font(.title3.weight(.semibold))
                    Text("This runs locally and keeps the original recording unchanged. Speaker labels may fall back to transcript-only mode.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Generate transcript") {
                        startProcessing()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!processingViewModel.canStart)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .accessibilityIdentifier(ProcessingAccessibilityID.startButton)
                }
                .cardStyle()
            } else {
                recoveryCard(
                    title: "No meeting audio is available",
                    message: "The screen recording and any successful files are still safe, but a transcript needs system or microphone audio. Start a new recording with at least one audio source enabled.",
                    actionTitle: "Start a new recording",
                    action: { coordinator.beginNewRecording() }
                )
            }

            secondaryMeetingActions
            technicalDetailsDisclosure
        }
    }

    private var processingView: some View {
        VStack(alignment: .leading, spacing: 26) {
            pageHeader(
                eyebrow: "CREATING TRANSCRIPT",
                title: coordinator.currentMeetingTitle,
                subtitle: "The original recording is safe while local processing runs.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )

            VStack(spacing: 22) {
                ProgressView()
                    .controlSize(.large)
                Text(processingProgressText)
                    .font(.title3.weight(.medium))
                Text("You can continue when this step finishes. Processing never uploads the meeting automatically.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 54)
            .frame(maxWidth: .infinity)
            .cardStyle()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(processingProgressText)
            .accessibilityIdentifier(ProcessingAccessibilityID.status)

            technicalDetailsDisclosure
        }
    }

    private var processingFailureView: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "TRANSCRIPT NEEDS ATTENTION",
                title: coordinator.currentMeetingTitle,
                subtitle: "The original recording is unchanged and safe to retry.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )
            recoveryCard(
                title: "The transcript could not be created",
                message: processingViewModel.state.errorMessage ?? "Processing stopped before a transcript was created.",
                actionTitle: "Retry transcript",
                action: retryProcessing,
                actionIdentifier: ProcessingAccessibilityID.retryButton
            )
            technicalDetailsDisclosure
        }
    }

    private func historicalMeetingRecoveryView(status: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "MEETING NEEDS ATTENTION",
                title: coordinator.currentMeetingTitle,
                subtitle: "Existing meeting files were not changed.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )
            VStack(alignment: .leading, spacing: 12) {
                Label("Meeting needs attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.recoveryStatus)
                Text(historicalMeetingRecoveryMessage(status: status))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start a new recording") {
                    coordinator.beginNewRecording()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(MeetingTaskAccessibilityID.startNewRecording)
            }
            .cardStyle()
            secondaryMeetingActions
            technicalDetailsDisclosure
        }
    }

    private func historicalMeetingRecoveryMessage(status: String) -> String {
        let explanation: String
        switch status {
        case "created":
            explanation = "This meeting never reached a confirmed recording."
        case "recording":
            explanation = "This meeting was still marked as recording when it was reopened, so a completed recording could not be confirmed."
        case "processing":
            explanation = "Transcript creation did not reach a confirmed result."
        default:
            explanation = "This meeting ended before it reached a usable result."
        }
        return "\(explanation) Existing meeting files were not changed. Start a new recording or delete this incomplete meeting."
    }

    private func transcriptLoadFailureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "TRANSCRIPT NEEDS ATTENTION",
                title: coordinator.currentMeetingTitle,
                subtitle: "The meeting recording is unchanged.",
                identifier: MeetingTaskAccessibilityID.detailHeading
            )
            VStack(alignment: .leading, spacing: 14) {
                Label("The transcript could not be opened", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.transcriptLoadError)
                if currentSessionHasProcessableAudio {
                    Button("Regenerate transcript", action: startProcessing)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!processingViewModel.canStart)
                        .keyboardShortcut("p", modifiers: [.command, .option])
                        .accessibilityIdentifier(ProcessingAccessibilityID.startButton)
                }
                HStack(spacing: 10) {
                    Button("Reload transcript", action: reloadTranscript)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(MeetingTaskAccessibilityID.reloadTranscript)
                }
            }
            .cardStyle()
            secondaryMeetingActions
            technicalDetailsDisclosure
        }
    }

    private var transcriptResultView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                pageHeader(
                    eyebrow: processingViewModel.state.phase == .degraded ? "TRANSCRIPT READY — SPEAKER LABELS LIMITED" : "TRANSCRIPT READY",
                    title: coordinator.currentMeetingTitle,
                    subtitle: transcriptViewModel.state.summary,
                    identifier: MeetingTaskAccessibilityID.detailHeading
                )
                Spacer(minLength: 20)
                HStack(spacing: 8) {
                    Button("Copy") {
                        Task { await transcriptActionViewModel.copyTranscript() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!transcriptActionViewModel.state.canCopy)
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .accessibilityIdentifier(TranscriptActionAccessibilityID.copyButton)

                    Button("Export…") {
                        Task { await transcriptActionViewModel.exportTranscript() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!transcriptActionViewModel.state.canExport)
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .accessibilityIdentifier(TranscriptActionAccessibilityID.exportButton)
                }
            }

            if let degradationReason = transcriptViewModel.state.degradationReason {
                Label(
                    "Speaker labels are unavailable, but the transcript is complete. \(degradationReason)",
                    systemImage: "person.2.slash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Speaker labels are anonymous and are not verified identities.",
                    systemImage: "person.2"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(transcriptViewModel.state.segments.enumerated()), id: \.element.id) { index, segment in
                    transcriptRow(segment)
                    if index < transcriptViewModel.state.segments.count - 1 {
                        Divider().padding(.leading, 88)
                    }
                }
            }
            .cardStyle(padding: 0)

            if let success = transcriptActionViewModel.state.successSummary {
                Label(success, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier(TranscriptActionAccessibilityID.successSummary)
            }
            secondaryMeetingActions
            technicalDetailsDisclosure
        }
    }

    private func transcriptRow(_ segment: TranscriptReviewVisibleSegment) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(segment.timestampLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
                .accessibilityIdentifier(TranscriptReviewAccessibilityID.timestamp(segment.id))
            VStack(alignment: .leading, spacing: 6) {
                if let speaker = segment.speakerDisplayLabel {
                    Text(shortSpeakerLabel(speaker))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(TranscriptReviewAccessibilityID.speakerLabel(segment.id))
                }
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(TranscriptReviewAccessibilityID.text(segment.id))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TranscriptReviewAccessibilityID.segmentRow(segment.id))
    }

    private var secondaryMeetingActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Button("Back to Meetings") {
                    coordinator.navigate(to: .meetings)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Delete meeting…") {
                    transcriptActionViewModel.requestDeleteConfirmation()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(!transcriptActionViewModel.state.canRequestDelete)
                .keyboardShortcut("d", modifiers: [.command, .option])
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteButton)
            }

            if transcriptActionViewModel.state.isDeletePromptVisible {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Delete \(coordinator.currentMeetingTitle)?")
                        .font(.headline)
                    Text("The meeting and its files inside the Meeting Assistant workspace will be removed. Exports saved elsewhere on this Mac will be kept.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePromptText)
                    HStack {
                        Button("Cancel") {
                            transcriptActionViewModel.cancelDelete()
                        }
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteCancelButton)
                        Button("Delete meeting", action: confirmDelete)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(!transcriptActionViewModel.state.canConfirmDelete)
                            .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteConfirmButton)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.22)))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePrompt)
            }

            if let failure = transcriptActionViewModel.state.failureSummary {
                recoveryCard(
                    title: "That action could not be completed",
                    message: failure,
                    actionTitle: "Dismiss",
                    action: transcriptActionViewModel.dismissFeedback
                )
                .accessibilityIdentifier(TranscriptActionAccessibilityID.errorSummary)
            }
        }
    }

    private var technicalDetailsDisclosure: some View {
        DisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let session = coordinator.currentSession {
                    technicalRow("Session ID", session.id)
                    technicalRow("Status", session.status)
                }
                ForEach(recordingViewModel.state.artifacts) { artifact in
                    technicalRow(
                        artifact.artifactType,
                        "\(artifact.captureStatus)\(artifact.path.map { " — \($0)" } ?? "")"
                    )
                }
                if let code = recordingViewModel.state.errorCode?.rawValue {
                    technicalRow("Recording error", code)
                }
                ForEach(Array(recordingViewModel.state.technicalDetails.enumerated()), id: \.offset) { _, detail in
                    technicalRow("Recording detail", detail)
                }
                ForEach(Array(recordingViewModel.state.warnings.enumerated()), id: \.offset) { _, warning in
                    technicalRow("Recording warning", warning)
                }
                if let code = processingViewModel.state.errorCode?.rawValue {
                    technicalRow("Processing error", code)
                }
                ForEach(Array(processingViewModel.state.errorDetails.enumerated()), id: \.offset) { _, detail in
                    technicalRow("Processing detail", detail)
                }
                if let detail = coordinator.transcriptTechnicalError {
                    technicalRow("Transcript load detail", detail)
                }
                ForEach(Array(transcriptActionViewModel.state.technicalDetails.enumerated()), id: \.offset) { _, detail in
                    technicalRow("Action detail", detail)
                }
            }
            .padding(.top, 10)
        }
        .font(.callout)
        .accessibilityIdentifier(MeetingTaskAccessibilityID.technicalDetails)
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader(
                eyebrow: "SETTINGS & DIAGNOSTICS",
                title: "Keep Meeting Assistant ready",
                subtitle: "Review local storage, macOS permissions, and the tools used to create transcripts.",
                identifier: MeetingTaskAccessibilityID.diagnosticsHeading
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Local workspace", systemImage: "internaldrive")
                    .font(.headline)
                Text(coordinator.workspaceURL.path)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(MeetingTaskAccessibilityID.workspacePath)
                Text("Meeting Assistant does not upload recordings or download dependencies automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = coordinator.workspaceTechnicalError {
                    DisclosureGroup("Workspace error details") {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                }
            }
            .cardStyle()

            PermissionDependencyStatusView(viewModel: permissionViewModel)
                .frame(minHeight: 360)
                .cardStyle(padding: 0)

            if !coordinator.workspaceIssues.isEmpty {
                DisclosureGroup("Unreadable meetings (\(coordinator.workspaceIssues.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(coordinator.workspaceIssues.enumerated()), id: \.offset) { _, issue in
                            Text("\(issue.path): \(issue.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func pageHeader(
        eyebrow: String,
        title: String,
        subtitle: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.tint)
            Text(title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.subtitle)
            Text("\(coordinator.route.title) selected")
                .font(.caption2)
                .foregroundStyle(.clear)
                .accessibilityLabel("\(coordinator.route.title) selected")
                .accessibilityIdentifier(MeetingTaskAccessibilityID.routeStatus)
        }
    }

    private func recoveryCard(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void,
        actionIdentifier: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionIdentifier {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(actionIdentifier)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
    }

    private func failureSummaryCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func technicalRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readinessTitle: String {
        switch permissionViewModel.state.phase {
        case .ready:
            return "Ready to record"
        case .checking:
            return "Checking your Mac…"
        case .blocked:
            return "Setup needs attention"
        case .failed:
            return "Setup check failed"
        case .idle:
            return "Check before recording"
        }
    }

    private var readinessMessage: String {
        switch permissionViewModel.state.phase {
        case .ready:
            return "Screen and audio settings are ready."
        case .checking:
            return "Meeting Assistant is checking permissions and local transcript tools."
        case .blocked:
            return "A required permission or local transcript tool is missing. Your settings are preserved; open Diagnostics for details."
        case .failed:
            return "The readiness check could not finish. Nothing was recorded; try the check again."
        case .idle:
            return "Meeting Assistant checks macOS permissions and local tools before it starts."
        }
    }

    private var readinessIcon: String {
        switch permissionViewModel.state.phase {
        case .ready:
            return "checkmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .blocked, .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "shield"
        }
    }

    private var readinessColor: Color {
        switch permissionViewModel.state.phase {
        case .ready:
            return .green
        case .checking, .idle:
            return .accentColor
        case .blocked, .failed:
            return .orange
        }
    }

    private var recordingAudioSummary: String {
        switch (
            coordinator.recordingDraft.captureSystemAudio,
            coordinator.recordingDraft.captureMicrophoneAudio
        ) {
        case (true, true):
            return "Entire screen · System audio · Microphone"
        case (true, false):
            return "Entire screen · System audio"
        case (false, true):
            return "Entire screen · Microphone"
        case (false, false):
            return "Entire screen · No audio"
        }
    }

    private var savedArtifactSummary: String {
        recordingSavedArtifactSummary(
            artifacts: recordingViewModel.state.artifacts,
            fallbackCount: coordinator.currentSession?.artifactCount ?? 0
        )
    }

    private var processingProgressText: String {
        processingViewModel.state.phase == .generatingSpeakerLabels
            ? "Adding anonymous speaker labels…"
            : "Transcribing meeting audio…"
    }

    private var currentSessionHasProcessableAudio: Bool {
        if let session = coordinator.currentSession, session.hasProcessableAudio {
            return true
        }
        let processable = Set(["mixed_audio", "system_audio", "microphone_audio"])
        return recordingViewModel.state.artifacts.contains {
            processable.contains($0.artifactType)
                && artifactIsUsable($0)
        }
    }

    private func artifactIsUsable(_ artifact: RecordingCommandArtifact) -> Bool {
        recordingArtifactIsUsable(artifact)
    }

    private func artifactStatusIcon(_ artifact: RecordingCommandArtifact) -> String {
        if recordingArtifactWasNotRequested(artifact) {
            return "minus.circle"
        }
        return artifactIsUsable(artifact) ? "checkmark.circle" : "exclamationmark.circle"
    }

    private func artifactStatusColor(_ artifact: RecordingCommandArtifact) -> Color {
        if recordingArtifactWasNotRequested(artifact) {
            return .secondary
        }
        return artifactIsUsable(artifact) ? .green : .orange
    }

    private func elapsedRecordingTime(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(coordinator.recordingStartedAt ?? date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func displayTitle(_ meeting: MeetingSessionSummary) -> String {
        if let title = meeting.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return "Untitled meeting"
    }

    private func meetingMetadata(_ meeting: MeetingSessionSummary) -> String {
        var parts = [meetingFriendlyDate(meeting.startedAt)]
        if let duration = meeting.durationLabel, !duration.isEmpty {
            parts.append(duration)
        }
        parts.append(meeting.artifactCount == 1 ? "1 file" : "\(meeting.artifactCount) files")
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ status: String, hasTranscript: Bool = false) -> Color {
        if historicalMeetingRecoveryStatus(status) != nil {
            return .orange
        }
        if status == "transcribed", !hasTranscript {
            return .orange
        }
        return .accentColor
    }

    private func shortSpeakerLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "Anonymous speaker ", with: "Speaker ")
            .replacingOccurrences(of: " (not a verified identity)", with: "")
    }

    @MainActor
    private func autoRefreshPreflightIfNeeded() async {
        guard autoRefreshPreflightOnAppear, !didAutoRefreshPreflight else {
            return
        }
        didAutoRefreshPreflight = true
        await permissionViewModel.refresh(workspaceURL: coordinator.workspaceURL)
    }
}

private extension View {
    func cardStyle(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
    }
}
