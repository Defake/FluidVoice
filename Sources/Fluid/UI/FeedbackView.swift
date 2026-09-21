import SwiftUI

struct FeedbackView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var category: FeedbackCategory = .issue
    @State private var message = ""
    @State private var email = ""
    @State private var includeDetails = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    private var draft: FeedbackSubmission {
        FeedbackSubmission(
            email: self.email,
            message: self.message,
            category: self.category,
            appDetails: self.includeDetails ? FeedbackSubmission.appDetails : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.xxl) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Make FluidVoice better.").font(self.theme.typography.displayTitle)
                    Text("Something getting in your way? Have an idea? Tell us.")
                        .font(self.theme.typography.statement).foregroundStyle(.secondary)
                }
                FluidGlassControlGroup { self.starInvitation }
                if self.sent { self.confirmation } else { self.form }
                self.footer
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(self.theme.metrics.spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var form: some View {
        ThemedCard(style: .standard, padding: self.theme.metrics.spacing.xxl) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What’s on your mind?").font(self.theme.typography.sectionTitle)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { self.categories }
                        VStack(alignment: .leading, spacing: 8) { self.categories }
                    }
                }
                self.messageField
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your email").font(self.theme.typography.bodyStrong)
                    TextField("Your email", text: self.$email, prompt: Text("you@example.com").foregroundColor(self.theme.palette.secondaryText))
                        .textFieldStyle(.plain).font(self.theme.typography.body)
                        .padding(12).fluidOnboardingEditorSurface()
                        .accessibilityLabel("Your email")
                    Text(self.email.isEmpty || FeedbackSubmission.isValidEmail(self.email)
                        ? "So we can follow up about your feedback."
                        : "Enter a valid email address, like you@example.com.")
                        .font(self.theme.typography.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Include app details").font(self.theme.typography.bodyStrong)
                        Text("App version and macOS version only. No recordings or logs.")
                            .font(self.theme.typography.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Toggle("Include app details", isOn: self.$includeDetails)
                        .labelsHidden().toggleStyle(.switch).fixedSize()
                        .accessibilityLabel("Include app and macOS versions")
                }
                if self.includeDetails {
                    Text(FeedbackSubmission.appDetails)
                        .font(self.theme.typography.codeCaption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let error = self.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { self.deliveryNote; Spacer(minLength: 0); self.sendButton }
                    VStack(alignment: .leading, spacing: 12) { self.deliveryNote; self.sendButton }
                }
            }
            .disabled(self.sending)
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.category.prompt).font(self.theme.typography.bodyStrong)
            ZStack(alignment: .topLeading) {
                TextEditor(text: self.$message)
                    .font(self.theme.typography.body).scrollContentBackground(.hidden)
                    .padding(10).frame(minHeight: 180, maxHeight: 240)
                    .accessibilityLabel(self.category.prompt)
                if self.message.isEmpty {
                    Text(self.category.hint).font(self.theme.typography.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 15).padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .fluidOnboardingEditorSurface()
            HStack(alignment: .top) {
                Text("Please leave out passwords and private information.")
                Spacer(minLength: 8)
                Text("\(self.message.utf16.count) / \(FeedbackSubmission.messageLimit)")
                    .monospacedDigit().fixedSize()
            }
            .font(self.theme.typography.caption).foregroundStyle(.secondary)
            if self.message.utf16.count > FeedbackSubmission.messageLimit {
                Text("Please shorten your message before sending.")
                    .font(self.theme.typography.caption).foregroundStyle(self.theme.palette.warning)
            }
        }
    }

    private var deliveryNote: some View {
        Text(self.sending ? "Sending your feedback…" : "Sent directly to the FluidVoice team.")
            .font(self.theme.typography.caption).foregroundStyle(.secondary)
    }

    private var sendButton: some View {
        Button { Task { await self.submit() } } label: {
            HStack(spacing: 8) {
                if self.sending { ProgressView().controlSize(.small) }
                Text(self.error == nil ? "Send feedback" : "Try again")
                Image(systemName: "arrow.up.right")
            }
        }
        .fluidGlassAction(prominent: true)
        .disabled(!self.draft.isValid || self.sending)
    }

    private var categories: some View {
        ForEach(FeedbackCategory.allCases, id: \.self) { category in
            Button { self.category = category } label: {
                Label(category.rawValue, systemImage: category.icon)
                    .font(self.theme.typography.bodySmallStrong)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.primary.opacity(self.category == category ? 0.10 : 0.025), in: Capsule())
                    .overlay(Capsule().strokeBorder(self.theme.palette.cardBorder.opacity(self.category == category ? 1 : 0.4)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(self.category == category ? .isSelected : [])
        }
    }

    private var confirmation: some View {
        ThemedCard(style: .standard, padding: self.theme.metrics.spacing.xxl) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.circle").font(self.theme.typography.displayTitle)
                Text("Thank you. Your feedback is in.").font(self.theme.typography.title)
                Text("We’ve received your message. If we need more details, we can reach you by email.")
                    .font(self.theme.typography.body).foregroundStyle(.secondary)
                Button("Send another message") { self.sent = false }.fluidGlassAction()
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
        }
    }

    @ViewBuilder private var starInvitation: some View {
        if #available(macOS 26, *), !self.reduceTransparency {
            self.starInvitationContent
                .padding(self.theme.metrics.spacing.xl)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: self.theme.metrics.corners.lg))
        } else {
            ThemedCard(style: .subtle, padding: self.theme.metrics.spacing.xl) {
                self.starInvitationContent
            }
        }
    }

    private var starInvitationContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { self.starMessage; Spacer(minLength: 0); self.starButton }
            VStack(alignment: .leading, spacing: 16) { self.starMessage; self.starButton }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footer: some View {
        if let url = URL(string: "https://github.com/sponsors/altic-dev") {
            Link("Support development ↗", destination: url)
                .font(self.theme.typography.caption).foregroundStyle(.secondary)
        }
    }

    private var starMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enjoying FluidVoice?").font(self.theme.typography.sectionTitle)
            Text("A star helps more people discover FluidVoice.")
                .font(self.theme.typography.bodySmall).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var starButton: some View {
        if let url = URL(string: "https://github.com/altic-dev/Fluid-oss") {
            Link(destination: url) {
                Label("Star on GitHub", systemImage: "star")
                    .fixedSize()
            }
            .fluidGlassAction()
            .help("Open the GitHub repository to give FluidVoice a star")
        }
    }

    @MainActor private func submit() async {
        guard !self.sending, self.draft.isValid else { return }
        let submission = self.draft
        self.sending = true
        self.error = nil
        defer { self.sending = false }
        do {
            try await FeedbackClient().send(submission)
            self.sent = true
            self.message = ""
            self.email = ""
            self.includeDetails = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
