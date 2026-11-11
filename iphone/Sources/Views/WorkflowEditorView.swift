import SwiftUI

/// Fokus-Modus für einen Workflow (Navigation-Push aus der Liste):
/// • oben ein persistierender Fortschrittsbalken (unter der Titelleiste)
/// • darunter der aktuelle Schritt in großer Typografie
/// • dann die komplette Schrittliste zum Abhaken (Wischen: Umbenennen/Löschen)
/// • untere Action-Bar (über der Safe Area) für die Hauptaktion
/// • oben rechts: Schritt hinzufügen (Sheet) + Menü (Bearbeiten/Zurücksetzen/Löschen)
struct WorkflowEditorView: View {
	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	let workflowId: String

	// Blätter-Zustände
	@State private var editingMeta = false      // Titel/Notizen (Sheet)
	@State private var addingStep = false       // Schritt hinzufügen (Sheet)
	@State private var renamingStep: WorkflowStep?
	@State private var renameDraft = ""
	@State private var confirmReset = false
	@State private var confirmDelete = false
	@State private var stepError: String?       // Fehler aus Schritt-Aktionen

	var body: some View {
		Group {
			if let wf = store.workflow(workflowId) {
				editor(wf)
			} else {
				ContentUnavailableView(
					"Workflow nicht gefunden",
					systemImage: "questionmark.circle",
					description: Text("Vielleicht wurde er gelöscht."))
					.navigationTitle("Fehler")
			}
		}
		.task {
			// Direkt per Deep-Link geöffnet? Daten nachladen.
			if store.workflow(workflowId) == nil { await store.loadWorkflows() }
		}
	}

	// MARK: – Blattaufbau

	@ViewBuilder
	private func editor(_ wf: Workflow) -> some View {
		let active = activeStep(wf)

		List {
			if let err = stepError ?? store.workflowsError {
				ErrorBanner(message: err, retry: {
					stepError = nil
					Task { await store.loadWorkflows() }
				})
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)
			}

			Section {
				if let step = active {
					focusCard(wf: wf, step: step)
				} else {
					completionCard
				}
			}

			Section("Schritte") {
				ForEach(wf.steps) { step in
					stepRow(workflow: wf, step: step, isActive: step.id == wf.activeStepId && !step.done)
				}
			}

			if !wf.notes.isEmpty {
				Section("Notizen") {
					Text(wf.notes)
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				}
			}
		}
		.listStyle(.insetGrouped)
		.refreshable { await store.loadWorkflows() }
		.navigationTitle(wf.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					addingStep = true
				} label: {
					Label("Schritt hinzufügen", systemImage: "plus")
				}
				Menu {
					Button("Titel & Notizen bearbeiten", systemImage: "pencil") {
						editingMeta = true
					}
					Button("Zurücksetzen", systemImage: "arrow.counterclockwise") {
						confirmReset = true
					}
					Divider()
					Button("Workflow löschen", systemImage: "trash", role: .destructive) {
						confirmDelete = true
					}
				} label: {
					Image(systemName: "ellipsis.circle")
				}
			}
		}
		// Fortschrittsbalken bleibt oben stehen.
		.safeAreaInset(edge: .top, spacing: 0) { progressHeader(wf) }
		// Hauptaktion immer griffbereit – über Home-Indikator und Tastatur.
		.safeAreaInset(edge: .bottom, spacing: 0) { actionBar(wf, active: active) }
		.sheet(isPresented: $editingMeta) {
			WorkflowFormSheet(workflow: wf)
				.presentationDetents([.medium, .large])
		}
		.sheet(isPresented: $addingStep) {
			AddStepSheet(workflowId: wf.id)
				.presentationDetents([.medium, .large])
		}
		.alert("Schritt umbenennen", isPresented: renameAlertBinding) {
			TextField("Schritt-Titel", text: $renameDraft)
			Button("Umbenennen") { commitRename(wf) }
			Button("Abbrechen", role: .cancel) { renamingStep = nil }
		}
		.confirmationDialog(
			"Workflow zurücksetzen?",
			isPresented: $confirmReset,
			titleVisibility: .visible
		) {
			Button("Alle Schritte öffnen") {
				Task { await store.resetWorkflow(wf.id) }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			Text("Alle erledigten Schritte werden wieder auf „offen“ gesetzt.")
		}
		.confirmationDialog(
			"Wirklich löschen?",
			isPresented: $confirmDelete,
			titleVisibility: .visible
		) {
			Button("Löschen", role: .destructive) {
				Task {
					await store.deleteWorkflow(wf.id)
					dismiss()
				}
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			Text("„\(wf.title)“ und alle seine Schritte werden dauerhaft entfernt.")
		}
	}

	// MARK: – Kopf & Karten

	/// Persistierender Fortschrittsbalken unter der Titelleiste.
	@ViewBuilder
	private func progressHeader(_ wf: Workflow) -> some View {
		let done = wf.steps.filter(\.done).count
		HStack(spacing: DS.Space.sm) {
			ProgressView(value: wf.progress)
				.progressViewStyle(.linear)
				.tint(wf.completedAt != nil ? DS.success : DS.accent)
			Text("\(done)/\(wf.steps.count)")
				.font(DS.Typo.meta.monospacedDigit())
				.foregroundStyle(DS.textSecondary)
				.frame(minWidth: 44, alignment: .trailing)
		}
		.padding(.horizontal, DS.Space.lg)
		.padding(.vertical, DS.Space.sm)
		.background(.bar)
	}

	/// Großer aktueller Schritt – der Fokus des gesamten Bildschirms.
	@ViewBuilder
	private func focusCard(wf: Workflow, step: WorkflowStep) -> some View {
		let index = wf.steps.firstIndex(where: { $0.id == step.id }) ?? 0
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			Text("Jetzt dran")
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.accent)
			Text(step.title)
				.font(.system(size: 28, weight: .bold))
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
			Text("Schritt \(index + 1) von \(wf.steps.count)")
				.font(DS.Typo.meta)
				.foregroundStyle(DS.textSecondary)
		}
		.padding(.vertical, DS.Space.xs)
		.listRowBackground(DS.tintSoft)
	}

	/// Grüner Abschluss, wenn alles erledigt ist.
	private var completionCard: some View {
		HStack(spacing: DS.Space.md) {
			Image(systemName: "checkmark.seal.fill")
				.font(.title2)
				.foregroundStyle(DS.success)
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text("Komplett erledigt")
					.font(.callout.weight(.semibold))
					.foregroundStyle(DS.success)
				Text("Starte von vorn, um alle Schritte zu öffnen.")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
			}
		}
		.padding(.vertical, DS.Space.xs)
	}

	// MARK: – Schrittzeile

	@ViewBuilder
	private func stepRow(workflow wf: Workflow, step: WorkflowStep, isActive: Bool) -> some View {
		HStack(spacing: DS.Space.md) {
			Button {
				Task { await store.toggleStep(workflowId: wf.id, stepId: step.id) }
			} label: {
				Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
					.font(.title3)
					.foregroundStyle(step.done ? DS.success : DS.textTertiary)
					.frame(width: 36, height: 36)   // große Trefferfläche
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel(step.done ? "Schritt wieder öffnen" : "Schritt abhaken")

			Text(step.title)
				.font(isActive ? .body.weight(.semibold) : .body)
				.strikethrough(step.done)
				.foregroundStyle(step.done ? DS.textSecondary : DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)

			Spacer(minLength: DS.Space.sm)

			if isActive {
				Chip(text: "Aktiv", color: DS.accent)
			}
		}
		.listRowBackground(isActive ? DS.tintSoft : Color.clear)
		.swipeActions(edge: .leading) {
			Button {
				renameDraft = step.title
				renamingStep = step
			} label: {
				Label("Umbenennen", systemImage: "pencil")
			}
			.tint(DS.accent)
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button(role: .destructive) {
				deleteStep(step)
			} label: {
				Label("Löschen", systemImage: "trash")
			}
		}
		.contextMenu {
			Button {
				renameDraft = step.title
				renamingStep = step
			} label: {
				Label("Umbenennen", systemImage: "pencil")
			}
			Button(role: .destructive) {
				deleteStep(step)
			} label: {
				Label("Löschen", systemImage: "trash")
			}
		}
	}

	// MARK: – Untere Action-Bar

	/// Große Primäraktion: aktuellen Schritt abhaken (bzw. neu starten).
	@ViewBuilder
	private func actionBar(_ wf: Workflow, active: WorkflowStep?) -> some View {
		VStack(spacing: 0) {
			Divider()
			if let step = active {
				Button {
					Task { await store.toggleStep(workflowId: wf.id, stepId: step.id) }
				} label: {
					Label("Schritt erledigen", systemImage: "checkmark")
				}
				.primaryButton()
			} else {
				Button {
					Task { await store.resetWorkflow(wf.id) }
				} label: {
					Label("Nochmal von vorn", systemImage: "arrow.counterclockwise")
				}
				.primaryButton()
			}
		}
		.padding(.horizontal, DS.Space.lg)
		.padding(.top, DS.Space.sm)
		.padding(.bottom, DS.Space.xs)
		.background(.bar)
	}

	// MARK: – Aktionen

	private func activeStep(_ wf: Workflow) -> WorkflowStep? {
		if let id = wf.activeStepId,
		   let step = wf.steps.first(where: { $0.id == id && !$0.done }) {
			return step
		}
		return wf.steps.first(where: { !$0.done })
	}

	private var renameAlertBinding: Binding<Bool> {
		Binding(
			get: { renamingStep != nil },
			set: { if !$0 { renamingStep = nil } }
		)
	}

	private func commitRename(_ wf: Workflow) {
		guard let step = renamingStep else { return }
		renamingStep = nil
		let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, trimmed != step.title else { return }
		Task {
			if let err = await store.renameStep(workflowId: wf.id, stepId: step.id, title: trimmed) {
				stepError = err
			}
		}
	}

	private func deleteStep(_ step: WorkflowStep) {
		Task {
			if let err = await store.deleteStep(workflowId: workflowId, stepId: step.id) {
				stepError = err
			}
		}
	}
}

// MARK: – Schritt hinzufügen (Sheet)

/// Kompaktes Sheet: ein Titel-Feld, Speichern als Bestätigungs-Button
/// (bleibt über der Tastatur erreichbar).
private struct AddStepSheet: View {
	let workflowId: String

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var title = ""
	@State private var error: String?
	@State private var saving = false

	@FocusState private var focused: Bool

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("z. B. Kapitel 3 lesen", text: $title, axis: .vertical)
						.focused($focused)
						.onSubmit(save)
				} footer: {
					Text("Der Schritt wird am Ende der Liste eingefügt.")
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
			.scrollDismissesKeyboard(.interactively)
			.navigationTitle("Neuer Schritt")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(saving ? "…" : "Hinzufügen", action: save)
						.disabled(saving
							|| title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
		.task {
			// Fokus, sobald das Sheet aufgebaut ist.
			try? await Task.sleep(for: .milliseconds(120))
			focused = true
		}
	}

	private func save() {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !saving else { return }
		saving = true
		error = nil
		Task {
			if let err = await store.addStep(workflowId: workflowId, title: trimmed) {
				saving = false
				error = err
			} else {
				dismiss()
			}
		}
	}
}
