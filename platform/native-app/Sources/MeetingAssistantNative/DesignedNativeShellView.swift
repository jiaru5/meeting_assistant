import SwiftUI

public struct DesignedNativeShellView: View {
    @ObservedObject private var shellViewModel: DesignedNativeShellViewModel
    @ObservedObject private var permissionViewModel: PermissionDependencyStatusViewModel
    @ObservedObject private var recordingViewModel: RecordingControlViewModel
    @ObservedObject private var processingViewModel: ProcessingStateViewModel
    @ObservedObject private var transcriptActionViewModel: TranscriptReviewActionsViewModel
    private let transcriptViewModel: TranscriptReviewViewModel

    public init(
        shellViewModel: DesignedNativeShellViewModel,
        permissionViewModel: PermissionDependencyStatusViewModel,
        recordingViewModel: RecordingControlViewModel,
        processingViewModel: ProcessingStateViewModel,
        transcriptViewModel: TranscriptReviewViewModel,
        transcriptActionViewModel: TranscriptReviewActionsViewModel
    ) {
        self.shellViewModel = shellViewModel
        self.permissionViewModel = permissionViewModel
        self.recordingViewModel = recordingViewModel
        self.processingViewModel = processingViewModel
        self.transcriptViewModel = transcriptViewModel
        self.transcriptActionViewModel = transcriptActionViewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        topNavigation
                        statusBoard
                        commandRail
                        section(.preflight) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Local-only workspace. No automatic upload, API call or dependency download is performed by the app.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.workspaceBoundary)

                                PermissionDependencyStatusView(viewModel: permissionViewModel)
                                    .frame(minHeight: 330, maxHeight: 380)
                            }
                        }
                        section(.recording) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Capture target: screen. System audio and microphone capture are requested through the recording command client.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.recordingSetup)

                                RecordingControlView(viewModel: recordingViewModel)
                            }
                        }
                        section(.artifacts) {
                            artifactBoard
                        }
                        section(.processing) {
                            VStack(alignment: .leading, spacing: 12) {
                                processingStepBoard
                                ProcessingStateView(viewModel: processingViewModel)
                            }
                        }
                        section(.transcript) {
                            TranscriptReviewView(viewModel: transcriptViewModel)
                        }
                        section(.actions) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Copy, export and delete are explicit user actions. Delete confirmation names the session and retains external exports.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if transcriptActionViewModel.state.isAvailable {
                                    TranscriptReviewActionsView(viewModel: transcriptActionViewModel)
                                } else {
                                    Text(transcriptActionViewModel.state.statusText)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(transcriptActionViewModel.state.statusText)
                                        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.exportDeleteUnavailable)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 920, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .onChange(of: shellViewModel.selectedSection) { _, section in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(section.rawValue, anchor: .top)
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.root)
        .onChange(of: permissionViewModel.state) { _, readiness in
            recordingViewModel.updateReadiness(readiness)
            processingViewModel.updateReadiness(readiness)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meeting Assistant")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(shellViewModel.selectedSectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(shellViewModel.selectedSectionLabel)
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.selectedSection)

            Text("Workflow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Meeting Assistant navigation")
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.navigation)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(shellViewModel.sections) { section in
                    Button {
                        shellViewModel.select(section)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(toneColor(section == shellViewModel.selectedSection ? "success" : "neutral"))
                                .frame(width: 4, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.callout.weight(section == shellViewModel.selectedSection ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(section == shellViewModel.selectedSection ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(section.title) navigation")
                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.navButton(section))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Meeting Assistant navigation")

            Spacer()

            Text("Release evidence still depends on the individual PV-MA gates for real capture, processing, OS integration and bundle readiness.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meeting Assistant")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Meeting Assistant")
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.heading)

            Text("Designed native app shell for local meeting recording, processing, transcript review, export and delete.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.subtitle)
        }
    }

    private var topNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workflow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Meeting Assistant navigation")
                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.navigation)

                Spacer(minLength: 12)

                Text(shellViewModel.selectedSectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(shellViewModel.selectedSectionLabel)
                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.selectedSection)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 124), spacing: 8, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(shellViewModel.sections) { section in
                    Button(section.title) {
                        shellViewModel.select(section)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityLabel("\(section.title) navigation")
                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.navButton(section))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var statusBoard: some View {
        let items = DesignedNativeShellViewModel.statusItems(
            readiness: permissionViewModel.state,
            recording: recordingViewModel.state,
            processing: processingViewModel.state,
            transcript: transcriptViewModel.state,
            actions: transcriptActionViewModel.state
        )

        return LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading),
            ],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(toneColor(item.tone))
                            .frame(width: 8, height: 8)
                        Text(item.value)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(item.value)")
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.status(item.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting Assistant status board")
        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.statusBoard)
    }

    private var commandRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 136), spacing: 8, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                Button("Start Recording") {
                    Task {
                        await recordingViewModel.start()
                    }
                }
                .disabled(!recordingViewModel.canStart)
                .accessibilityIdentifier(RecordingControlAccessibilityID.startButton)

                Button("Stop Recording") {
                    Task {
                        await recordingViewModel.stop()
                    }
                }
                .disabled(!recordingViewModel.canStop)
                .accessibilityIdentifier(RecordingControlAccessibilityID.stopButton)

                Button("Start Processing") {
                    Task {
                        await processingViewModel.start()
                    }
                }
                .disabled(!processingViewModel.canStart)
                .accessibilityIdentifier(ProcessingAccessibilityID.startButton)

                Button("Retry Processing") {
                    Task {
                        await processingViewModel.retry()
                    }
                }
                .disabled(!processingViewModel.canRetry)
                .accessibilityIdentifier(ProcessingAccessibilityID.retryButton)

                Button("Copy Transcript") {
                    Task {
                        await transcriptActionViewModel.copyTranscript()
                    }
                }
                .disabled(!transcriptActionViewModel.state.canCopy)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.copyButton)

                Button("Export Markdown") {
                    Task {
                        await transcriptActionViewModel.exportTranscript()
                    }
                }
                .disabled(!transcriptActionViewModel.state.canExport)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.exportButton)

                Button("Delete Session") {
                    transcriptActionViewModel.requestDeleteConfirmation()
                }
                .disabled(!transcriptActionViewModel.state.canRequestDelete)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteButton)
            }

            if transcriptActionViewModel.state.isDeletePromptVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text(transcriptActionViewModel.state.deletePromptText ?? "Confirm delete before removing the session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(transcriptActionViewModel.state.deletePromptText ?? "Confirm delete before removing the session.")
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePromptText)

                    HStack(spacing: 8) {
                        Button("Confirm Delete") {
                            Task {
                                await transcriptActionViewModel.confirmDelete()
                            }
                        }
                        .disabled(!transcriptActionViewModel.state.canConfirmDelete)
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteConfirmButton)

                        Button("Cancel Delete") {
                            transcriptActionViewModel.cancelDelete()
                        }
                        .disabled(!transcriptActionViewModel.state.canCancelDelete)
                        .accessibilityIdentifier(TranscriptActionAccessibilityID.deleteCancelButton)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(TranscriptActionAccessibilityID.deletePrompt)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary meeting actions")
        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.commandRail)
    }

    private var artifactBoard: some View {
        let rows = DesignedNativeShellViewModel.artifactRows(from: recordingViewModel.state.artifacts)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    statusDot(for: row.status)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(row.artifactType): \(row.status)")
                            .font(.body.weight(.medium))
                            .accessibilityLabel("\(row.artifactType): \(row.status)")
                            .accessibilityIdentifier(DesignedNativeShellAccessibilityID.artifactStatus(row.artifactType))

                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(row.detail)
                            .accessibilityIdentifier(DesignedNativeShellAccessibilityID.artifactDetail(row.artifactType))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
    }

    private var processingStepBoard: some View {
        let steps = DesignedNativeShellViewModel.processingSteps(from: processingViewModel.state)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(step.title)
                        .font(.caption.weight(.semibold))
                        .frame(width: 132, alignment: .leading)
                    Text(step.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title): \(step.status)")
                .accessibilityIdentifier(DesignedNativeShellAccessibilityID.processingStep(step.id))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func section<Content: View>(
        _ section: DesignedNativeShellSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(section.title)
                    .accessibilityIdentifier(DesignedNativeShellAccessibilityID.sectionHeading(section))

                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .id(section.rawValue)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    section == shellViewModel.selectedSection
                        ? toneColor("success")
                        : Color(nsColor: .separatorColor),
                    lineWidth: section == shellViewModel.selectedSection ? 2 : 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(DesignedNativeShellAccessibilityID.section(section))
    }

    private func statusDot(for status: String) -> some View {
        Circle()
            .fill(toneColor(tone(forArtifactStatus: status)))
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    private func tone(forArtifactStatus status: String) -> String {
        switch status {
        case "available":
            return "success"
        case "degraded":
            return "fallback"
        case "missing", "failed":
            return "error"
        case "pending":
            return "neutral"
        default:
            return "warning"
        }
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "success":
            return Color(red: 0.12, green: 0.48, blue: 0.32)
        case "warning":
            return Color(red: 0.68, green: 0.45, blue: 0.08)
        case "error":
            return Color(red: 0.72, green: 0.18, blue: 0.16)
        case "recording":
            return Color(red: 0.82, green: 0.12, blue: 0.12)
        case "fallback":
            return Color(red: 0.42, green: 0.32, blue: 0.70)
        default:
            return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
