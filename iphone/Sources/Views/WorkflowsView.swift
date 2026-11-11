import SwiftUI

/// Workflow-Liste für iPhone: kompakte Zeilen (Titel, Fortschrittsbalken,
/// Vorschau des aktiven Schritts) in zwei Abschnitten (Offen/Erledigt).
/// • „+“ oben rechts legt an (Sheet, mittel/groß)
/// • Wisch nach links löscht (mit Rückfrage), Kontextmenü: Bearbeiten/Löschen
/// • Zeilen-Push öffnet den Fokus-Modus (WorkflowEditorView)
/// • Ziehen am Listenkopf lädt neu (.refreshable)
struct WorkflowsView: View {
	@Environment(AppStore.self) private var store

	@State private var creating = false
	@State private var editingWorkflow: Workflow?
	@State private var deleteCandidate: Workflow?

	private var openWorkflows: [Workflow] { store.workflows.filter { $0.completedAt == nil } }
	private var doneWorkflows: [Workflow] { store.workflows.filter { $0.completedAt != nil } }

	var body: some View {
		NavigationStack {
			Group {
				if store.workflowsBusy && store.workflows.isEmpty {
					TimelineSkeleton()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if store.workflows.isEmpty {
					ContentUnavailableView {
						Label("Keine Workflows", systemImage: "checklist")
					} description: {
						Text(store.workflowsError
							?? "Lege hier einen Workflow an – er erscheint auch in der Web-App.")
					} actions: {
						Button("Neuer Workflow") { creating = true }
							.buttonStyle(.borderedProminent)
							.tint(DS.accent)
					}
				} else {
					list
				}
			}
			.navigationTitle("Workflows")
			.navigationBarTitleDisplayMode(.large)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						creating = true
					} label: {
						Label("Neuer Workflow", systemImage: "plus")
					}
					.accessibilityLabel("Neuer Workflow")
				}
			}
			.navigationDestination(for: String.self) { id in
				WorkflowEditorView(workflowId: id)
			}
		}
		.sheet(isPresented: $creating) {
			WorkflowFormSheet()
				.presentationDetents([.medium, .large])
		}
		.sheet(item: $editingWorkflow) { wf in
			WorkflowFormSheet(workflow: wf)
				.presentationDetents([.medium, .large])
		}
		.confirmationDialog(
			"Wirklich löschen?",
			isPresented: Binding(
				get: { deleteCandidate != nil },
				set: { if !$0 { deleteCandidate = nil } }
			),
			titleVisibility: .visible
		) {
			Button("Löschen", role: .destructive) {
				if let wf = deleteCandidate {
					deleteCandidate = nil
					Task { await store.deleteWorkflow(wf.id) }
				}
			}
			Button("Abbrechen", role: .cancel) { deleteCandidate = nil }
		} message: {
			if let wf = deleteCandidate {
				Text("„\(wf.title)“ und alle seine Schritte werden dauerhaft entfernt.")
			}
		}
		.task {
			if store.workflows.isEmpty { await store.loadWorkflows() }
		}
	}

	// MARK: – Liste

	private var list: some View {
		List {
			if let err = store.workflowsError {
				ErrorBanner(message: err, retry: {
					Task { await store.loadWorkflows() }
				})
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)
			}

			Section("Offen") {
				ForEach(openWorkflows) { wf in
					row(wf)
				}
			}

			if !doneWorkflows.isEmpty {
				Section("Erledigt") {
					ForEach(doneWorkflows) { wf in
						row(wf)
					}
				}
			}
		}
		.listStyle(.insetGrouped)
		.refreshable { await store.loadWorkflows() }
	}

	/// Eine Zeile: Navigation-Push zum Fokus-Modus, Wisch-Aktion + Kontextmenü.
	@ViewBuilder
	private func row(_ wf: Workflow) -> some View {
		NavigationLink(value: wf.id) {
			WorkflowRow(workflow: wf)
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button(role: .destructive) {
				deleteCandidate = wf
			} label: {
				Label("Löschen", systemImage: "trash")
			}
		}
		.contextMenu {
			Button {
				editingWorkflow = wf
			} label: {
				Label("Bearbeiten", systemImage: "pencil")
			}
			Button(role: .destructive) {
				deleteCandidate = wf
			} label: {
				Label("Löschen", systemImage: "trash")
			}
		}
	}
}

// MARK: – Workflow-Zeile (Liste)

/// Kompakte Zeile: Titel (+ Erledigt-Chip bzw. Prozent), Fortschrittsbalken,
/// Zähler links + Vorschau des nächsten offenen Schritts rechts.
private struct WorkflowRow: View {
	let workflow: Workflow

	private var doneCount: Int { workflow.steps.filter(\.done).count }
	private var percent: Int { Int((workflow.progress * 100).rounded()) }
	private var isDone: Bool { workflow.completedAt != nil }
	private var nextStep: WorkflowStep? { workflow.steps.first { !$0.done } }

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			HStack(spacing: DS.Space.sm) {
				Text(workflow.title)
					.font(.body.weight(.semibold))
					.foregroundStyle(DS.textPrimary)
					.lineLimit(2)
				Spacer(minLength: DS.Space.sm)
				if isDone {
					Chip(text: "Erledigt", color: DS.success, systemImage: "checkmark.circle.fill")
				} else {
					Text("\(percent) %")
						.font(DS.Typo.meta.monospacedDigit())
						.foregroundStyle(DS.textTertiary)
				}
			}

			ProgressView(value: workflow.progress)
				.progressViewStyle(.linear)
				.tint(isDone ? DS.success : DS.accent)

			HStack(spacing: DS.Space.xs) {
				Text("\(doneCount)/\(workflow.steps.count) Schritte")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
				Spacer(minLength: DS.Space.sm)
				if let step = nextStep {
					Image(systemName: "arrow.right")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(DS.textTertiary)
					Text(step.title)
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
						.lineLimit(1)
						.frame(maxWidth: 170, alignment: .trailing)
				}
			}
		}
		.padding(.vertical, DS.Space.xs)
		.contentShape(Rectangle())
	}
}

// MARK: – Anlegen/Bearbeiten-Formular (Sheet)

/// Anlegen (Titel + Schrittliste, native Zeilen statt Zeilen-Texteditor) oder
/// Bearbeiten (Titel + Notizen) eines Workflows – wird von der Liste und vom
/// Fokus-Modus als Sheet präsentiert (.presentationDetents mittel/groß).
/// Speichert über store.createWorkflow bzw. store.updateWorkflowEdit.
struct WorkflowFormSheet: View {
	/// Eingabezeile (stabile IDs für ForEach-Bindings + Wisch-Löschen).
	private struct StepDraft: Identifiable {
		var id = UUID()
		var text: String = ""
	}

	/// nil = neuer Workflow, sonst der zu bearbeitende.
	private let workflow: Workflow?

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var title: String
	@State private var drafts: [StepDraft]
	@State private var notes: String
	@State private var error: String?
	@State private var saving = false

	@FocusState private var titleFocused: Bool

	private var isCreate: Bool { workflow == nil }

	init(workflow: Workflow? = nil) {
		self.workflow = workflow
		_title = State(initialValue: workflow?.title ?? "")
		_notes = State(initialValue: workflow?.notes ?? "")
		// Beim Anlegen direkt eine leere Schritt-Zeile anbieten.
		_drafts = State(initialValue: workflow == nil ? [StepDraft()] : [])
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("z. B. Projektabschluss – Woche 12", text: $title)
						.focused($titleFocused)
						.onSubmit(save)
				} header: {
					Text("Titel")
				}

				if isCreate {
					Section {
						ForEach(Array($drafts.enumerated()), id: \.element.wrappedValue.id) { idx, step in
							TextField("Schritt \(idx + 1)", text: step.text)
						}
						.onDelete { drafts.remove(atOffsets: $0) }

						Button {
							drafts.append(StepDraft())
						} label: {
							Label("Weiterer Schritt", systemImage: "plus.circle.fill")
								.foregroundStyle(DS.accent)
						}
					} header: {
						Text("Schritte")
					} footer: {
						Text("Wischen zum Entfernen – du kannst Schritte auch später ergänzen.")
					}
				} else {
					Section {
						TextField("Ergänzungen, Links, Kontext …", text: $notes, axis: .vertical)
							.lineLimit(3...8)
					} header: {
						Text("Notizen")
					}
				}

				if let error {
					Section {
						ErrorBanner(message: error)
							.listRowBackground(Color.clear)
							.listRowSeparator(.hidden)
					}
				}
			}
			.formStyle(.grouped)
			.navigationTitle(isCreate ? "Neuer Workflow" : "Workflow bearbeiten")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
			}
			.safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
		}
		.task {
			// Fokus, sobald das Sheet aufgebaut ist.
			try? await Task.sleep(for: .milliseconds(120))
			titleFocused = true
		}
	}

	// MARK: – Speichern

	/// Primär-Button unten – liegt über Tastatur und Home-Indikator.
	private var saveBar: some View {
		VStack(spacing: 0) {
			Divider()
			Button(action: save) {
				if saving {
					HStack(spacing: DS.Space.xs) {
						ProgressView().controlSize(.small)
						Text(isCreate ? "Wird angelegt …" : "Wird gespeichert …")
					}
				} else {
					Text(isCreate ? "Workflow anlegen" : "Speichern")
				}
			}
			.primaryButton()
			.disabled(saving || !canSave)
			.padding(.horizontal, DS.Space.lg)
			.padding(.top, DS.Space.sm)
			.padding(.bottom, DS.Space.xs)
		}
		.background(.bar)
	}

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
				// Schritte: geleere Zeilen fallen raus.
				let steps = drafts
					.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
					.filter { !$0.isEmpty }
				failure = await store.createWorkflow(title: trimmed, steps: steps)
			} else {
				failure = await store.updateWorkflowEdit(workflow!, title: trimmed, notes: notes)
			}
			saving = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}
}
