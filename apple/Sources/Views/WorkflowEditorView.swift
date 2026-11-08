import SwiftUI

/// Anlegen-/Bearbeiten-Dialog für Workflows als Sheet-Inhalt.
/// Ohne Workflow-Argument = Anlegen (Titel + Schritte, einer pro Zeile – wie in
/// der Web-App); mit Workflow = Bearbeiten (Titel + Notizen, via PATCH).
/// Speichert über store.createWorkflow bzw. store.updateWorkflowEdit; bei
/// Erfolg schließt sich der Dialog, sonst erscheint ein ErrorBanner.
struct WorkflowEditorView: View {
	/// nil = neuer Workflow, sonst der zu bearbeitende.
	private let workflow: Workflow?

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var title: String
	@State private var stepsText: String
	@State private var notes: String
	@State private var error: String?
	@State private var saving = false

	@FocusState private var titleFocused: Bool

	private var isCreate: Bool { workflow == nil }

	init(workflow: Workflow? = nil) {
		self.workflow = workflow
		_title = State(initialValue: workflow?.title ?? "")
		_stepsText = State(initialValue: "")
		_notes = State(initialValue: workflow?.notes ?? "")
	}

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text(isCreate ? "Neuer Workflow" : "Workflow bearbeiten")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				fieldLabel("Titel")
				TextField("z. B. Projektabschluss – Woche 12", text: $title)
					.focused($titleFocused)
			}

			if isCreate {
				VStack(alignment: .leading, spacing: DS.Space.xs) {
					fieldLabel("Schritte (einer pro Zeile)")
					TextEditor(text: $stepsText)
						.font(.callout)
						.scrollContentBackground(.hidden)
						.frame(height: 130)
						.fieldChrome()
					Text("Leerzeilen werden ignoriert – du kannst Schritte auch später ergänzen.")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
				}
			} else {
				VStack(alignment: .leading, spacing: DS.Space.xs) {
					fieldLabel("Notizen")
					TextEditor(text: $notes)
						.font(.callout)
						.scrollContentBackground(.hidden)
						.frame(height: 130)
						.fieldChrome()
				}
			}

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button(action: save) {
					if saving {
						HStack(spacing: DS.Space.xs) {
							ProgressView().controlSize(.small)
							Text(isCreate ? "Wird angelegt …" : "Wird gespeichert …")
						}
					} else {
						Text(isCreate ? "Workflow anlegen" : "Workflow speichern")
					}
				}
				.keyboardShortcut(.defaultAction)
				.primaryButton()
				.disabled(saving || !canSave)
			}
			.padding(.top, DS.Space.xxs)
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
		.onAppear {
			// Fokus, sobald das Sheet aufgebaut ist.
			Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(120))
				titleFocused = true
			}
		}
	}

	// MARK: – Speichern

	private var canSave: Bool {
		!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func save() {
		guard canSave, !saving else { return }
		saving = true
		error = nil
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let failure: String?
			if isCreate {
				// Schritte wie in der Web-App: einer pro Zeile, leerer Text raus.
				let steps = stepsText
					.split(separator: "\n", omittingEmptySubsequences: true)
					.map { $0.trimmingCharacters(in: .whitespaces) }
					.filter { !$0.isEmpty }
				failure = await store.createWorkflow(title: trimmed, steps: steps)
			} else {
				failure = await store.updateWorkflowEdit(
					workflow!, title: trimmed, notes: notes)
			}
			saving = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}

	private func fieldLabel(_ text: String) -> some View {
		Text(text)
			.font(DS.Typo.metaStrong)
			.foregroundStyle(DS.textSecondary)
	}
}
