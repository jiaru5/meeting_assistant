import CryptoKit
import Foundation
import Testing
@testable import MeetingAssistantNative

@Suite("Transcript review")
struct TranscriptReviewViewModelTests {
    @Test
    func formatsTimestampsWithMinutesAndHours() {
        #expect(TranscriptReviewFormatter.timestampLabel(startMS: 0, endMS: 65_000) == "00:00-01:05")
        #expect(TranscriptReviewFormatter.timestampLabel(startMS: 3_600_000, endMS: 3_723_000) == "1:00:00-1:02:03")
    }

    @Test
    func exposesOrderedSegmentRows() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                sessionTitle: "Planning Review",
                transcript: transcript(
                    segments: [
                        segment("seg-2", startMS: 20_000, endMS: 22_000, text: "Second."),
                        segment("seg-1", startMS: 1_000, endMS: 2_000, text: "First."),
                    ]
                )
            )
        )

        #expect(viewModel.state.heading == "Planning Review")
        #expect(viewModel.state.summary == "Transcript has 2 segments for review.")
        #expect(viewModel.state.segments.map(\.id) == ["seg-1", "seg-2"])
        #expect(viewModel.state.segments.map(\.text) == ["First.", "Second."])
    }

    @Test
    func mapsSpeakerLabelsOnlyFromObjectArrayMappingWhenLabelIsNotVerified() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 1_000, endMS: 2_000, text: "Mapped.", speakerLabel: "SPEAKER_99"),
                        segment("seg-2", startMS: 2_000, endMS: 3_000, text: "No mapping.", speakerLabel: "SPEAKER_02"),
                        segment("seg-3", startMS: 3_000, endMS: 4_000, text: "Verified mapping."),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "session-transcript",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "session-transcript",
                            isVerifiedIdentity: false
                        ),
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_03",
                            sessionID: "session-transcript",
                            isVerifiedIdentity: true
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                        SpeakerLabelSegmentMapping(segmentID: "seg-3", label: "SPEAKER_03"),
                    ]
                )
            )
        )

        #expect(viewModel.state.segments[0].speakerDisplayLabel == "Anonymous speaker SPEAKER_01 (not a verified identity)")
        #expect(viewModel.state.segments[1].speakerDisplayLabel == nil)
        #expect(viewModel.state.segments[2].speakerDisplayLabel == nil)
    }

    @Test
    func keepsSpeakerWordingAnonymousAndNonVerified() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 0, endMS: 1_000, text: "Hello."),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "session-transcript",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "session-transcript",
                            isVerifiedIdentity: false
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                    ]
                )
            )
        )

        #expect(viewModel.state.segments.first?.speakerDisplayLabel == "Anonymous speaker SPEAKER_01 (not a verified identity)")
    }

    @Test
    func ignoresSpeakerLabelsArtifactFromDifferentSession() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 0, endMS: 1_000, text: "Cross-session artifact."),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "other-session",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "other-session",
                            isVerifiedIdentity: false
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                    ]
                )
            )
        )

        #expect(viewModel.state.segments.first?.speakerDisplayLabel == nil)
    }

    @Test
    func ignoresSpeakerLabelEntryFromDifferentSession() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 0, endMS: 1_000, text: "Cross-session label."),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "session-transcript",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "other-session",
                            isVerifiedIdentity: false
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                    ]
                )
            )
        )

        #expect(viewModel.state.segments.first?.speakerDisplayLabel == nil)
    }

    @Test
    func exposesTranscriptOnlyDegradationReasonWithoutChangingTranscript() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 0, endMS: 1_000, text: "Transcript text remains visible."),
                    ]
                ),
                speakerLabelsDegradationReason: "speaker labeling runtime unavailable"
            )
        )

        #expect(viewModel.state.contentState == .available)
        #expect(viewModel.state.segments.first?.text == "Transcript text remains visible.")
        #expect(viewModel.state.degradationReason == "speaker labeling runtime unavailable")
    }

    @Test
    func suppressesTranscriptOnlyDegradationWhenAnySpeakerLabelIsVisible() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(
                    segments: [
                        segment("seg-1", startMS: 0, endMS: 1_000, text: "Labeled transcript."),
                        segment("seg-2", startMS: 1_000, endMS: 2_000, text: "Unlabeled transcript."),
                    ]
                ),
                speakerLabels: SpeakerLabelsReviewArtifact(
                    sessionID: "session-transcript",
                    labels: [
                        SpeakerLabelReviewEntry(
                            label: "SPEAKER_01",
                            sessionID: "session-transcript",
                            isVerifiedIdentity: false
                        ),
                    ],
                    segmentMapping: [
                        SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
                    ]
                ),
                speakerLabelsDegradationReason: "speaker labeling runtime unavailable"
            )
        )

        #expect(viewModel.state.segments[0].speakerDisplayLabel == "Anonymous speaker SPEAKER_01 (not a verified identity)")
        #expect(viewModel.state.degradationReason == nil)
    }

    @Test
    func exposesMissingTranscriptState() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(transcript: nil)
        )

        #expect(viewModel.state.contentState == .missing)
        #expect(viewModel.state.summary == "Transcript is missing for this session.")
        #expect(viewModel.state.segments.isEmpty)
    }

    @Test
    func exposesEmptyTranscriptState() {
        let viewModel = TranscriptReviewViewModel(
            input: TranscriptReviewInput(
                transcript: transcript(segments: []),
                speakerLabelsDegradationReason: "speaker labeling skipped"
            )
        )

        #expect(viewModel.state.contentState == .empty)
        #expect(viewModel.state.summary == "Transcript has no segments to review.")
        #expect(viewModel.state.degradationReason == "speaker labeling skipped")
    }

    @Test
    func exposesStableAccessibilityIdentifiers() {
        #expect(TranscriptReviewAccessibilityID.heading == "ma.transcript.heading")
        #expect(TranscriptReviewAccessibilityID.summary == "ma.transcript.summary")
        #expect(TranscriptReviewAccessibilityID.segmentRow("seg-1") == "ma.transcript.segmentRow.seg-1")
        #expect(TranscriptReviewAccessibilityID.timestamp("seg-1") == "ma.transcript.timestamp.seg-1")
        #expect(TranscriptReviewAccessibilityID.text("seg-1") == "ma.transcript.text.seg-1")
        #expect(TranscriptReviewAccessibilityID.speakerLabel("seg-1") == "ma.transcript.speakerLabel.seg-1")
        #expect(TranscriptReviewAccessibilityID.degradation == "ma.transcript.degradation")
        #expect(TranscriptReviewAccessibilityID.empty == "ma.transcript.empty")
        #expect(TranscriptReviewAccessibilityID.missing == "ma.transcript.missing")
    }

    @Test
    func decodesOnlyFrozenTranscriptAndSpeakerLabelFields() throws {
        let transcriptJSON = """
        {
          "id": "transcript-1",
          "session_id": "session-transcript",
          "source_artifact_id": "artifact-audio",
          "status": "succeeded",
          "segments": [
            {
              "segment_id": "seg-1",
              "start_ms": 0,
              "end_ms": 1000,
              "text": "Hello.",
              "speaker_label": "SPEAKER_01"
            }
          ],
          "created_at": "2026-06-29T00:00:00Z"
        }
        """.data(using: .utf8)!
        let speakerJSON = """
        {
          "session_id": "session-transcript",
          "labels": [
            {
              "label": "SPEAKER_01",
              "session_id": "session-transcript",
              "is_verified_identity": false,
              "display_name": "ignored"
            }
          ],
          "segment_mapping": [
            {
              "segment_id": "seg-1",
              "label": "SPEAKER_01",
              "created_at": "2026-06-29T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let decodedTranscript = try JSONDecoder().decode(TranscriptReviewTranscript.self, from: transcriptJSON)
        let decodedSpeakers = try JSONDecoder().decode(SpeakerLabelsReviewArtifact.self, from: speakerJSON)

        #expect(decodedTranscript.id == "transcript-1")
        #expect(decodedTranscript.sourceArtifactID == "artifact-audio")
        #expect(decodedTranscript.segments.first?.speakerLabel == "SPEAKER_01")
        #expect(decodedSpeakers.labels == [
            SpeakerLabelReviewEntry(
                label: "SPEAKER_01",
                sessionID: "session-transcript",
                isVerifiedIdentity: false
            ),
        ])
        #expect(decodedSpeakers.segmentMapping == [
            SpeakerLabelSegmentMapping(segmentID: "seg-1", label: "SPEAKER_01"),
        ])
    }
}

@Suite("Transcript review workspace loader")
struct TranscriptReviewWorkspaceLoaderTests {
    @Test
    func loadsTranscriptAndSpeakerLabelsFromWorkspaceArtifacts() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-loader"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let transcriptURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let speakerURL = sessionRoot.appendingPathComponent("artifacts/speaker_labels.json")
        let transcriptChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: transcriptURL)
        let speakerChecksum = try writeJSON(
            speakerPayload(
                sessionID: sessionID,
                labels: [
                    [
                        "label": "SPEAKER_01",
                        "session_id": sessionID,
                        "is_verified_identity": false,
                    ],
                ],
                segmentMapping: [
                    [
                        "segment_id": "seg-1",
                        "label": "SPEAKER_01",
                    ],
                ]
            ),
            to: speakerURL
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: "Workspace transcript",
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: transcriptChecksum
                ),
                artifact(
                    id: "artifact-speakers",
                    sessionID: sessionID,
                    artifactType: "speaker_labels",
                    path: speakerURL.path,
                    checksum: speakerChecksum
                ),
            ]
        )

        let input = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
        let viewModel = TranscriptReviewViewModel(input: input)

        #expect(input.sessionTitle == "Workspace transcript")
        #expect(input.transcript?.id == "transcript-loader")
        #expect(input.speakerLabels?.labels.first?.label == "SPEAKER_01")
        #expect(viewModel.state.heading == "Workspace transcript")
        #expect(viewModel.state.segments.first?.timestampLabel == "00:00-00:05")
        #expect(viewModel.state.segments.first?.speakerDisplayLabel == "Anonymous speaker SPEAKER_01 (not a verified identity)")
        #expect(viewModel.state.degradationReason == nil)
    }

    @Test
    func loadsTranscriptOnlyDegradationReasonFromSessionArtifactMetadata() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-transcript-only"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let transcriptURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let speakerURL = sessionRoot.appendingPathComponent("artifacts/speaker_labels.json")
        let transcriptChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: transcriptURL)
        let speakerChecksum = try writeJSON(
            speakerPayload(sessionID: sessionID, labels: [], segmentMapping: []),
            to: speakerURL
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: "Transcript-only workspace",
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: transcriptChecksum
                ),
                artifact(
                    id: "artifact-speakers",
                    sessionID: sessionID,
                    artifactType: "speaker_labels",
                    path: "artifacts/speaker_labels.json",
                    captureStatus: "degraded",
                    checksum: speakerChecksum,
                    degradationReason: "speaker labeling runtime unavailable"
                ),
            ]
        )

        let input = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
        let viewModel = TranscriptReviewViewModel(input: input)

        #expect(input.speakerLabelsDegradationReason == "speaker labeling runtime unavailable")
        #expect(viewModel.state.degradationReason == "speaker labeling runtime unavailable")
        #expect(viewModel.state.segments.first?.text == "Workspace transcript text.")
    }

    @Test
    func mapsMissingTranscriptArtifactToMissingTranscriptInput() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-missing-transcript"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: "Missing transcript workspace",
            artifacts: []
        )

        let input = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)

        #expect(input.sessionTitle == "Missing transcript workspace")
        #expect(input.transcript == nil)
        #expect(TranscriptReviewViewModel(input: input).state.contentState == .missing)
    }

    @Test
    func rejectsSessionIDTraversalBeforeReadingWorkspace() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: "../outside")
            Issue.record("Expected session traversal to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            #expect(error == .invalidSessionID("../outside"))
        }
    }

    @Test
    func rejectsSessionMetadataSymlinkBeforeDecode() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-metadata-symlink"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let targetURL = workspace.appendingPathComponent("external-session.json")
        _ = try writeJSON(
            sessionPayload(sessionRoot: sessionRoot, sessionID: sessionID, title: nil, artifacts: []),
            to: targetURL
        )
        try FileManager.default.createSymbolicLink(
            at: sessionRoot.appendingPathComponent("session.json"),
            withDestinationURL: targetURL
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected session metadata symlink to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .sessionMetadataSymlink(let path) = error else {
                Issue.record("Expected sessionMetadataSymlink, got \(error).")
                return
            }
            #expect(path.hasSuffix("/session.json"))
        }
    }

    @Test
    func rejectsSessionMetadataHardlinkBeforeDecode() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-metadata-hardlink"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let sourceURL = workspace.appendingPathComponent("session-source.json")
        let linkedURL = sessionRoot.appendingPathComponent("session.json")
        _ = try writeJSON(
            sessionPayload(sessionRoot: sessionRoot, sessionID: sessionID, title: nil, artifacts: []),
            to: sourceURL
        )
        try FileManager.default.linkItem(at: sourceURL, to: linkedURL)

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected session metadata hardlink to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .sessionMetadataHardlink(let path) = error else {
                Issue.record("Expected sessionMetadataHardlink, got \(error).")
                return
            }
            #expect(path.hasSuffix("/session.json"))
        }
    }

    @Test
    func rejectsSessionMetadataDirectoryBeforeDecode() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-metadata-directory"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("session.json", isDirectory: true),
            withIntermediateDirectories: false
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected session metadata directory to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .sessionMetadataNotRegularFile(let path) = error else {
                Issue.record("Expected sessionMetadataNotRegularFile, got \(error).")
                return
            }
            #expect(path.hasSuffix("/session.json"))
        }
    }

    @Test
    func rejectsArtifactPathEscape() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-path-escape"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let outsideURL = workspace.appendingPathComponent("outside-transcript.json")
        let outsideChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: outsideURL)
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: outsideURL.path,
                    checksum: outsideChecksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected escaped artifact path to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactPathEscape(let artifactID, _) = error else {
                Issue.record("Expected artifactPathEscape, got \(error).")
                return
            }
            #expect(artifactID == "artifact-transcript")
        }
    }

    @Test
    func rejectsSymlinkArtifact() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-symlink"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let targetURL = workspace.appendingPathComponent("external-transcript.json")
        let targetChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: targetURL)
        let symlinkURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: targetChecksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected symlink artifact to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactSymlink(let artifactID, _) = error else {
                Issue.record("Expected artifactSymlink, got \(error).")
                return
            }
            #expect(artifactID == "artifact-transcript")
        }
    }

    @Test
    func rejectsHardlinkArtifact() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-hardlink"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let sourceURL = workspace.appendingPathComponent("external-transcript.json")
        let linkedURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let checksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: sourceURL)
        try FileManager.default.linkItem(at: sourceURL, to: linkedURL)
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: checksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected hardlink artifact to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactHardlink(let artifactID, _) = error else {
                Issue.record("Expected artifactHardlink, got \(error).")
                return
            }
            #expect(artifactID == "artifact-transcript")
        }
    }

    @Test
    func rejectsNonRegularArtifact() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-non-regular-artifact"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("artifacts/transcript.json", isDirectory: true),
            withIntermediateDirectories: false
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: "sha256:\(String(repeating: "0", count: 64))"
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected non-regular artifact to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactNotRegularFile(let artifactID, _) = error else {
                Issue.record("Expected artifactNotRegularFile, got \(error).")
                return
            }
            #expect(artifactID == "artifact-transcript")
        }
    }

    @Test
    func rejectsChecksumDrift() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-checksum-drift"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let transcriptURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let originalChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: transcriptURL)
        _ = try writeJSON(
            transcriptPayload(sessionID: sessionID, text: "Mutated transcript text."),
            to: transcriptURL
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: originalChecksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected checksum drift to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .checksumDrift(let artifactID, let expected, let actual) = error else {
                Issue.record("Expected checksumDrift, got \(error).")
                return
            }
            #expect(artifactID == "artifact-transcript")
            #expect(expected == originalChecksum)
            #expect(actual != originalChecksum)
        }
    }

    @Test
    func rejectsCrossSessionSpeakerLabelsPayload() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-cross-speaker"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let transcriptURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let speakerURL = sessionRoot.appendingPathComponent("artifacts/speaker_labels.json")
        let transcriptChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: transcriptURL)
        let speakerChecksum = try writeJSON(
            speakerPayload(
                sessionID: "other-session",
                labels: [
                    [
                        "label": "SPEAKER_01",
                        "session_id": "other-session",
                        "is_verified_identity": false,
                    ],
                ],
                segmentMapping: [
                    [
                        "segment_id": "seg-1",
                        "label": "SPEAKER_01",
                    ],
                ]
            ),
            to: speakerURL
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: transcriptChecksum
                ),
                artifact(
                    id: "artifact-speakers",
                    sessionID: sessionID,
                    artifactType: "speaker_labels",
                    path: "artifacts/speaker_labels.json",
                    checksum: speakerChecksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected cross-session speaker payload to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactSessionMismatch(let artifactID, let expected, let actual) = error else {
                Issue.record("Expected artifactSessionMismatch, got \(error).")
                return
            }
            #expect(artifactID == "artifact-speakers")
            #expect(expected == sessionID)
            #expect(actual == "other-session")
        }
    }

    @Test
    func rejectsCrossSessionSpeakerLabelsRegistryEntry() throws {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionID = "session-cross-speaker-registry"
        let sessionRoot = try createSessionRoot(workspace: workspace, sessionID: sessionID)
        let transcriptURL = sessionRoot.appendingPathComponent("artifacts/transcript.json")
        let speakerURL = sessionRoot.appendingPathComponent("artifacts/speaker_labels.json")
        let transcriptChecksum = try writeJSON(transcriptPayload(sessionID: sessionID), to: transcriptURL)
        let speakerChecksum = try writeJSON(
            speakerPayload(sessionID: sessionID, labels: [], segmentMapping: []),
            to: speakerURL
        )
        try writeSession(
            sessionRoot: sessionRoot,
            sessionID: sessionID,
            title: nil,
            artifacts: [
                artifact(
                    id: "artifact-transcript",
                    sessionID: sessionID,
                    artifactType: "transcript_text",
                    path: "artifacts/transcript.json",
                    checksum: transcriptChecksum
                ),
                artifact(
                    id: "artifact-speakers",
                    sessionID: "other-session",
                    artifactType: "speaker_labels",
                    path: "artifacts/speaker_labels.json",
                    checksum: speakerChecksum
                ),
            ]
        )

        do {
            _ = try TranscriptReviewWorkspaceLoader.load(workspaceURL: workspace, sessionID: sessionID)
            Issue.record("Expected cross-session speaker registry entry to be rejected.")
        } catch let error as TranscriptReviewWorkspaceLoaderError {
            guard case .artifactSessionMismatch(let artifactID, let expected, let actual) = error else {
                Issue.record("Expected artifactSessionMismatch, got \(error).")
                return
            }
            #expect(artifactID == "artifact-speakers")
            #expect(expected == sessionID)
            #expect(actual == "other-session")
        }
    }
}

private func transcript(
    segments: [TranscriptReviewSegment]
) -> TranscriptReviewTranscript {
    TranscriptReviewTranscript(
        id: "transcript-fixture",
        sessionID: "session-transcript",
        sourceArtifactID: "artifact-normalized-audio",
        status: "succeeded",
        segments: segments
    )
}

private func temporaryWorkspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ma-native-loader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func createSessionRoot(workspace: URL, sessionID: String) throws -> URL {
    let sessionRoot = workspace
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(sessionID, isDirectory: true)
    try FileManager.default.createDirectory(
        at: sessionRoot.appendingPathComponent("artifacts", isDirectory: true),
        withIntermediateDirectories: true
    )
    return sessionRoot
}

private func writeSession(
    sessionRoot: URL,
    sessionID: String,
    title: String?,
    artifacts: [[String: Any]]
) throws {
    _ = try writeJSON(
        sessionPayload(sessionRoot: sessionRoot, sessionID: sessionID, title: title, artifacts: artifacts),
        to: sessionRoot.appendingPathComponent("session.json")
    )
}

private func sessionPayload(
    sessionRoot: URL,
    sessionID: String,
    title: String?,
    artifacts: [[String: Any]]
) -> [String: Any] {
    var payload: [String: Any] = [
        "id": sessionID,
        "source_type": "imported_media",
        "status": "transcribed",
        "started_at": "2026-06-29T00:00:00Z",
        "workspace_dir": sessionRoot.path,
        "created_at": "2026-06-29T00:00:00Z",
        "updated_at": "2026-06-29T00:00:00Z",
        "artifacts": artifacts,
    ]
    if let title {
        payload["title"] = title
    }
    return payload
}

private func artifact(
    id: String,
    sessionID: String,
    artifactType: String,
    path: String,
    captureStatus: String = "available",
    checksum: String,
    degradationReason: String? = nil
) -> [String: Any] {
    var payload: [String: Any] = [
        "id": id,
        "session_id": sessionID,
        "artifact_type": artifactType,
        "path": path,
        "format": "json",
        "capture_status": captureStatus,
        "checksum": checksum,
        "created_at": "2026-06-29T00:00:00Z",
    ]
    if let degradationReason {
        payload["degradation_reason"] = degradationReason
    }
    return payload
}

private func transcriptPayload(
    sessionID: String,
    text: String = "Workspace transcript text."
) -> [String: Any] {
    [
        "id": "transcript-loader",
        "session_id": sessionID,
        "source_artifact_id": "artifact-normalized-audio",
        "status": "succeeded",
        "segments": [
            [
                "segment_id": "seg-1",
                "start_ms": 0,
                "end_ms": 5_000,
                "text": text,
            ],
        ],
        "created_at": "2026-06-29T00:00:00Z",
    ]
}

private func speakerPayload(
    sessionID: String,
    labels: [[String: Any]],
    segmentMapping: [[String: Any]]
) -> [String: Any] {
    [
        "session_id": sessionID,
        "transcript_id": "transcript-loader",
        "label_status": labels.isEmpty ? "transcript_only" : "labeled",
        "degradation_reason": labels.isEmpty ? "speaker labeling runtime unavailable" : "",
        "labels": labels,
        "segment_mapping": segmentMapping,
        "created_at": "2026-06-29T00:00:00Z",
    ]
}

@discardableResult
private func writeJSON(_ payload: Any, to url: URL) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}

private func segment(
    _ id: String,
    startMS: Int,
    endMS: Int,
    text: String,
    speakerLabel: String? = nil
) -> TranscriptReviewSegment {
    TranscriptReviewSegment(
        segmentID: id,
        startMS: startMS,
        endMS: endMS,
        text: text,
        speakerLabel: speakerLabel
    )
}
