import Foundation
import SwiftUI

public enum MeetingWorkspaceRoute: String, CaseIterable, Equatable, Identifiable, Sendable {
    case meetings
    case newRecording
    case meetingDetail
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meetings:
            return "Meetings"
        case .newRecording:
            return "New recording"
        case .meetingDetail:
            return "Meeting detail"
        case .diagnostics:
            return "Settings & diagnostics"
        }
    }
}

public enum MeetingWorkspaceActivity: String, Equatable, Sendable {
    case idle
    case startingRecording
    case recording
    case saving
    case saveNeedsAttention
    case processing
    case deleting

    public var locksNavigation: Bool {
        self != .idle
    }
}

public enum MeetingDeletionWorkspaceReconciliation: Equatable, Sendable {
    case sessionPresent(MeetingSessionSummary)
    case sessionMissing
    case workspaceUnreadable
}

public struct MeetingRecordingDraft: Equatable, Sendable {
    public var title: String
    public var captureSystemAudio: Bool
    public var captureMicrophoneAudio: Bool

    public init(
        title: String = "",
        captureSystemAudio: Bool = true,
        captureMicrophoneAudio: Bool = true
    ) {
        self.title = title
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophoneAudio = captureMicrophoneAudio
    }

    public var normalizedTitle: String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum SelectedMeetingLoadOutcome: Sendable {
    case loaded(MeetingSessionSummary)
    case missing
    case failed(String)
}

private struct DeletionWorkspaceReload: Sendable {
    let snapshot: MeetingSessionWorkspaceSnapshot
    let selectedMeeting: MeetingSessionSummary?
    let selectedMeetingError: String?
}

@MainActor
public final class MeetingWorkspaceCoordinator: ObservableObject {
    @Published public private(set) var route: MeetingWorkspaceRoute
    @Published public private(set) var recentSessions: [MeetingSessionSummary]
    @Published public private(set) var currentSession: MeetingSessionSummary?
    @Published public var recordingDraft: MeetingRecordingDraft
    @Published public private(set) var activity: MeetingWorkspaceActivity = .idle
    @Published public private(set) var workspaceIssues: [MeetingSessionWorkspaceIssue] = []
    @Published public private(set) var workspaceError: String?
    @Published public private(set) var workspaceTechnicalError: String?
    @Published public private(set) var transcriptLoadError: String?
    @Published public private(set) var transcriptTechnicalError: String?
    @Published public private(set) var notice: String?
    @Published public private(set) var recordingStartedAt: Date?

    public let workspaceURL: URL
    private let repository: MeetingSessionWorkspaceRepository
    private var seededSessions: [MeetingSessionSummary]
    private let injectedSessionIDs: Set<String>
    private var selectionRevision = 0

    public init(
        workspaceURL: URL,
        repository: MeetingSessionWorkspaceRepository = MeetingSessionWorkspaceRepository(),
        initialSessions: [MeetingSessionSummary] = [],
        initialRoute: MeetingWorkspaceRoute = .meetings,
        recordingDraft: MeetingRecordingDraft = MeetingRecordingDraft()
    ) {
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.repository = repository
        self.seededSessions = initialSessions
        self.injectedSessionIDs = Set(initialSessions.map(\.id))
        self.recentSessions = initialSessions
        self.route = initialRoute
        self.recordingDraft = recordingDraft
    }

    public var navigationIsLocked: Bool {
        activity.locksNavigation
    }

    public var currentMeetingTitle: String {
        if let title = currentSession?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return "Untitled meeting"
    }

    public func refreshSessions() {
        do {
            let snapshot = try repository.load(workspaceURL: workspaceURL)
            workspaceIssues = snapshot.issues
            workspaceError = nil
            workspaceTechnicalError = nil
            recentSessions = mergedSessions(snapshot.sessions, seededSessions)
        } catch {
            workspaceError = "Meeting Assistant could not read the local meeting workspace. Your existing files were not changed."
            workspaceTechnicalError = error.localizedDescription
            recentSessions = seededSessions
        }
    }

    public func navigate(to nextRoute: MeetingWorkspaceRoute) {
        guard !navigationIsLocked else {
            return
        }
        selectionRevision += 1
        if nextRoute == .meetingDetail, currentSession == nil {
            route = .meetings
            return
        }
        route = nextRoute
    }

    public func beginNewRecording() {
        guard !navigationIsLocked else {
            return
        }
        selectionRevision += 1
        currentSession = nil
        transcriptLoadError = nil
        transcriptTechnicalError = nil
        notice = nil
        route = .newRecording
    }

    /// Loads the selected meeting off the main actor and publishes it only
    /// after checksum-backed artifact validation succeeds. Injected sessions
    /// are an explicit deterministic UI-test boundary; workspace sessions are
    /// never promoted from the lightweight Recent projection alone.
    @discardableResult
    public func open(_ session: MeetingSessionSummary) async -> MeetingSessionSummary? {
        guard !navigationIsLocked else {
            return nil
        }
        selectionRevision += 1
        let requestedRevision = selectionRevision
        let repository = repository
        let workspaceURL = workspaceURL
        let outcome = await Task.detached(priority: .userInitiated) {
            do {
                if let selected = try repository.loadSelectedSession(
                    workspaceURL: workspaceURL,
                    sessionID: session.id
                ) {
                    return SelectedMeetingLoadOutcome.loaded(selected)
                }
                return .missing
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value

        guard selectionRevision == requestedRevision,
              !navigationIsLocked else {
            return nil
        }

        let selectedSession: MeetingSessionSummary
        switch outcome {
        case .loaded(let selected):
            selectedSession = selected
        case .missing where injectedSessionIDs.contains(session.id):
            selectedSession = session
        case .missing:
            currentSession = nil
            transcriptLoadError = nil
            transcriptTechnicalError = nil
            notice = nil
            workspaceError = "This meeting is no longer available in the local workspace. Choose another meeting or refresh the list."
            workspaceTechnicalError = "Selected meeting \(session.id) was not found or is marked deleted."
            route = .meetings
            return nil
        case .failed(let technicalError):
            currentSession = nil
            transcriptLoadError = nil
            transcriptTechnicalError = nil
            notice = nil
            workspaceError = "Meeting Assistant could not safely open this meeting. Your existing files were not changed. Choose another meeting or repair the workspace."
            workspaceTechnicalError = technicalError
            route = .meetings
            return nil
        }

        currentSession = selectedSession
        recentSessions = replacingSession(selectedSession, in: recentSessions)
        workspaceError = nil
        workspaceTechnicalError = nil
        transcriptLoadError = nil
        transcriptTechnicalError = nil
        notice = nil
        route = .meetingDetail
        return selectedSession
    }

    public func recordingWillStart() {
        selectionRevision += 1
        activity = .startingRecording
        transcriptLoadError = nil
        notice = nil
    }

    public func recordingDidStart(sessionID: String, now: Date = Date()) {
        let timestamp = ISO8601DateFormatter().string(from: now)
        currentSession = MeetingSessionSummary(
            id: sessionID,
            title: recordingDraft.normalizedTitle,
            status: "recording",
            startedAt: timestamp,
            endedAt: nil,
            updatedAt: timestamp,
            durationLabel: nil,
            artifactCount: 0,
            hasTranscript: false,
            hasSpeakerLabels: false,
            hasProcessableAudio: false
        )
        recordingStartedAt = now
        activity = .recording
        route = .meetingDetail
    }

    public func recordingWillSave() {
        activity = .saving
    }

    public func recordingDidSave(_ recordingState: RecordingControlState, now: Date = Date()) {
        guard let sessionID = recordingState.sessionID else {
            activity = .idle
            return
        }
        let existing = currentSession
        let processableTypes = Set(["mixed_audio", "system_audio", "microphone_audio"])
        let availableArtifacts = recordingState.artifacts.filter {
            $0.captureStatus == "available"
        }
        let hasProcessableAudio = recordingState.artifacts.contains {
            processableTypes.contains($0.artifactType)
                && ($0.captureStatus == "available" || $0.captureStatus == "degraded")
                && $0.path?.isEmpty == false
                && $0.checksum?.isEmpty == false
        }
        let timestamp = ISO8601DateFormatter().string(from: now)
        let saved = MeetingSessionSummary(
            id: sessionID,
            title: existing?.title ?? recordingDraft.normalizedTitle,
            status: "recorded",
            startedAt: existing?.startedAt ?? timestamp,
            endedAt: timestamp,
            updatedAt: timestamp,
            durationLabel: elapsedLabel(from: recordingStartedAt, to: now),
            artifactCount: availableArtifacts.count,
            hasTranscript: false,
            hasSpeakerLabels: false,
            hasProcessableAudio: hasProcessableAudio
        )
        currentSession = saved
        seededSessions = mergedSessions([saved], seededSessions)
        recentSessions = mergedSessions([saved], recentSessions)
        recordingStartedAt = nil
        activity = .idle
        route = .meetingDetail
    }

    public func recordingDidFail(hasActiveSession: Bool) {
        if !hasActiveSession {
            activity = .idle
            currentSession = nil
            route = .newRecording
        } else {
            activity = .saveNeedsAttention
            route = .meetingDetail
        }
    }

    public func processingWillStart() {
        activity = .processing
        transcriptLoadError = nil
        transcriptTechnicalError = nil
    }

    public func processingDidFinish() {
        activity = .idle
        route = .meetingDetail
    }

    public func processingDidFail() {
        activity = .idle
        route = .meetingDetail
    }

    public func deletionWillStart() {
        guard currentSession != nil, activity == .idle else {
            return
        }
        activity = .deleting
        notice = nil
    }

    public func deletionDidFail() {
        activity = .idle
        route = currentSession == nil ? .meetings : .meetingDetail
    }

    /// Re-reads the managed workspace after every delete attempt so the UI does
    /// not keep transcript or artifact capabilities from the pre-delete
    /// projection. The command response decides only whether success may be
    /// announced; the refreshed workspace decides whether the meeting remains.
    public func reconcileDeletionAttempt(
        sessionID: String,
        commandReportedDeletion: Bool
    ) async -> MeetingDeletionWorkspaceReconciliation {
        notice = nil
        transcriptLoadError = nil
        transcriptTechnicalError = nil

        do {
            let repository = repository
            let workspaceURL = workspaceURL
            let reload = try await Task.detached(priority: .userInitiated) {
                let snapshot = try repository.load(workspaceURL: workspaceURL)
                guard snapshot.sessions.contains(where: { $0.id == sessionID }) else {
                    return DeletionWorkspaceReload(
                        snapshot: snapshot,
                        selectedMeeting: nil,
                        selectedMeetingError: nil
                    )
                }
                do {
                    return DeletionWorkspaceReload(
                        snapshot: snapshot,
                        selectedMeeting: try repository.loadSelectedSession(
                            workspaceURL: workspaceURL,
                            sessionID: sessionID
                        ),
                        selectedMeetingError: nil
                    )
                } catch {
                    return DeletionWorkspaceReload(
                        snapshot: snapshot,
                        selectedMeeting: nil,
                        selectedMeetingError: error.localizedDescription
                    )
                }
            }.value
            let snapshot = reload.snapshot
            workspaceIssues = snapshot.issues
            seededSessions.removeAll { $0.id == sessionID }

            if let selectedMeetingError = reload.selectedMeetingError {
                recentSessions = mergedSessions(snapshot.sessions, seededSessions)
                    .filter { $0.id != sessionID }
                currentSession = nil
                recordingStartedAt = nil
                activity = .idle
                route = .meetings
                workspaceError = "Meeting Assistant could not safely reload the meeting after the delete attempt. Old meeting details were cleared to avoid showing stale files."
                workspaceTechnicalError = selectedMeetingError
                return .workspaceUnreadable
            }

            if let refreshed = reload.selectedMeeting {
                seededSessions = mergedSessions([refreshed], seededSessions)
                recentSessions = replacingSession(
                    refreshed,
                    in: mergedSessions(snapshot.sessions, seededSessions)
                )
                currentSession = refreshed
                activity = .idle
                route = .meetingDetail

                if commandReportedDeletion {
                    workspaceError = "Meeting Assistant could not verify the deletion because the meeting is still present in the refreshed workspace. Its current files were reloaded."
                } else {
                    workspaceError = nil
                }
                workspaceTechnicalError = nil
                return .sessionPresent(refreshed)
            }

            recentSessions = mergedSessions(snapshot.sessions, seededSessions)
                .filter { $0.id != sessionID }
            currentSession = nil
            recordingStartedAt = nil
            activity = .idle
            route = .meetings

            if let issue = snapshot.issues.first(where: { $0.sessionID == sessionID }) {
                workspaceError = "Meeting Assistant could not safely reload the meeting after the delete attempt. Old meeting details were cleared to avoid showing stale files."
                workspaceTechnicalError = "\(issue.path): \(issue.reason)"
                return .workspaceUnreadable
            }

            workspaceTechnicalError = nil
            if commandReportedDeletion {
                workspaceError = nil
                notice = "Meeting deleted. Exports saved outside the workspace were kept."
            } else {
                workspaceError = "Delete reported a problem, and the meeting is no longer present in the refreshed workspace. Old meeting details were cleared; no deletion success was assumed."
            }
            return .sessionMissing
        } catch {
            seededSessions.removeAll { $0.id == sessionID }
            recentSessions.removeAll { $0.id == sessionID }
            currentSession = nil
            recordingStartedAt = nil
            workspaceIssues = []
            transcriptLoadError = nil
            transcriptTechnicalError = nil
            activity = .idle
            notice = nil
            route = .meetings
            workspaceError = "Meeting Assistant could not refresh the workspace after the delete attempt. Old meeting details were cleared to avoid showing stale files."
            workspaceTechnicalError = error.localizedDescription
            return .workspaceUnreadable
        }
    }

    public func transcriptDidLoad(for sessionID: String) {
        guard currentSession?.id == sessionID else {
            return
        }
        transcriptLoadError = nil
        transcriptTechnicalError = nil
        if let currentSession {
            let updated = MeetingSessionSummary(
                id: currentSession.id,
                title: currentSession.title,
                status: "transcribed",
                startedAt: currentSession.startedAt,
                endedAt: currentSession.endedAt,
                updatedAt: currentSession.updatedAt,
                durationLabel: currentSession.durationLabel,
                artifactCount: currentSession.artifactCount,
                hasTranscript: true,
                hasSpeakerLabels: currentSession.hasSpeakerLabels,
                hasProcessableAudio: currentSession.hasProcessableAudio
            )
            self.currentSession = updated
            seededSessions = mergedSessions([updated], seededSessions)
            recentSessions = mergedSessions([updated], recentSessions)
        }
        route = .meetingDetail
    }

    public func transcriptDidFailToLoad(_ error: Error) {
        if currentSession?.hasProcessableAudio == true {
            transcriptLoadError = "The transcript could not be opened. The original recording is still safe. Regenerate the transcript from the saved meeting audio, or reload it after repairing the meeting files."
        } else {
            transcriptLoadError = "The transcript could not be opened. The original recording and any available files are still safe, but this meeting has no processable audio for regeneration. You can reload after repairing the meeting files or delete the meeting."
        }
        transcriptTechnicalError = error.localizedDescription
        activity = .idle
        route = .meetingDetail
    }

    public func clearTranscriptError() {
        transcriptLoadError = nil
        transcriptTechnicalError = nil
    }

    public func deletionDidFinish(sessionID: String) {
        selectionRevision += 1
        seededSessions.removeAll { $0.id == sessionID }
        recentSessions.removeAll { $0.id == sessionID }
        currentSession = nil
        recordingStartedAt = nil
        transcriptLoadError = nil
        transcriptTechnicalError = nil
        activity = .idle
        notice = "Meeting deleted. Exports saved outside the workspace were kept."
        route = .meetings
        refreshSessions()
    }

    public func clearCurrentSession(returnToMeetings: Bool = true) {
        selectionRevision += 1
        currentSession = nil
        recordingStartedAt = nil
        transcriptLoadError = nil
        transcriptTechnicalError = nil
        activity = .idle
        if returnToMeetings {
            route = .meetings
        }
    }

    private func mergedSessions(
        _ preferred: [MeetingSessionSummary],
        _ fallback: [MeetingSessionSummary]
    ) -> [MeetingSessionSummary] {
        var seen = Set<String>()
        return (preferred + fallback).filter { seen.insert($0.id).inserted }
    }

    private func replacingSession(
        _ replacement: MeetingSessionSummary,
        in sessions: [MeetingSessionSummary]
    ) -> [MeetingSessionSummary] {
        sessions.map { session in
            session.id == replacement.id ? replacement : session
        }
    }

    private func elapsedLabel(from start: Date?, to end: Date) -> String? {
        guard let start else {
            return nil
        }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
