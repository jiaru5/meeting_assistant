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
