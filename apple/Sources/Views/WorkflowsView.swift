import SwiftUI

/// Workflow-Liste mit Fortschritt; Detailansicht = Fokus-Modus der Web-App.
/// Vollverwaltung wie in der Web-App: anlegen, bearbeiten (Titel/Notizen),
/// löschen, Schritte hinzufügen/umbenennen/löschen.
struct WorkflowsView: View {
	@Environment(AppStore.self) private var store

	@State private var creating = false
	@State private var editingWorkflow: Workflow?
	@State private var deleteCandidate: Workflow?

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				SectionHeader("Workflows", subtitle: "Schrittpläne im Fokus-Modus") {
					AccentPillButton(title: "Neuer Workflow", systemImage: "plus") {
						creating = true
					}
					.keyboardShortcut("n")
					.help("Neuer Workflow (⌘N)")
				}

				Group {
					if store.workflowsBusy && store.workflows.isEmpty {
						TimelineSkeleton()
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else if store.workflows.isEmpty {
						EmptyStateView(
							title: "Keine Workflows",
							systemImage: "checklist",
							description: store.workflowsError
								?? "Lege hier einen Workflow an – er erscheint auch in der Web-App.",
							actionTitle: "Neuer Workflow",
							action: { creating = true })
					} else {
						ScrollView {
							VStack(spacing: DS.Space.md) {
								if let err = store.workflowsError {
									ErrorBanner(message: err, retry: {
										Task { await store.loadWorkflows() }
									})
								}
								ForEach(store.workflows) { wf in
									NavigationLink(value: wf.id) {
										WorkflowCard(workflow: wf)
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
									.buttonStyle(.plain)
								}
							}
							.padding(DS.Space.xl)
							.frame(maxWidth: 640, alignment: .leading)
							.frame(maxWidth: .infinity, alignment: .topLeading)
						}
						.refreshable { await store.loadWorkflows() }
					}
				}
			}
			.navigationDestination(for: String.self) { id in
				WorkflowDetailView(workflowId: id)
			}
		}
		.sheet(isPresented: $creating) {
			WorkflowEditorView()
		}
		.sheet(item: $editingWorkflow) { wf in
			WorkflowEditorView(workflow: wf)
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
}

// MARK: – Workflow-Karte (Liste)

/// Karte in der Workflow-Liste: Titel, linearer Fortschritt, Zähler, Erledigt-Chip.
/// Rechtsklick/Kontextmenü: Bearbeiten + Löschen (siehe WorkflowsView).
private struct WorkflowCard: View {
	let workflow: Workflow

	@State private var hovering = false

	private var doneCount: Int { workflow.steps.filter(\.done).count }
	private var percent: Int { Int((workflow.progress * 100).rounded()) }

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			HStack(spacing: DS.Space.sm) {
				Text(workflow.title)
					.font(DS.Typo.cardTitle)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(2)
				Spacer(minLength: DS.Space.sm)
				if workflow.completedAt != nil {
					Chip(text: "Erledigt", color: DS.success, systemImage: "checkmark.circle.fill")
				}
			}

			ProgressView(value: workflow.progress)
				.progressViewStyle(.linear)
				.tint(workflow.completedAt != nil ? DS.success : DS.accent)

			HStack(spacing: DS.Space.sm) {
				Text("\(doneCount)/\(workflow.steps.count) Schritte")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
				Spacer(minLength: DS.Space.sm)
				Text("\(percent) %")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textTertiary)
			}
		}
		.padding(DS.Space.lg)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsCard()
		.overlay(
			RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
				.fill(DS.rowHover.opacity(hovering ? 1 : 0))
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
	}
}

// MARK: – Detail (Fokus-Modus)

struct WorkflowDetailView: View {
	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss
	let workflowId: String

	// Bearbeiten/Löschen des Workflows selbst
	@State private var editing = false
	@State private var confirmDelete = false

	// Schritt-Bearbeitung (inline umbenennen, löschen mit Rückfrage)
	@State private var editingStepId: String?
	@State private var stepDraft = ""
	@State private var stepDeleteCandidate: WorkflowStep?
	@State private var hoveredStepId: String?
	@State private var newStepTitle = ""
	@State private var stepBusy = false

	var body: some View {
		Group {
			if let wf = store.workflow(workflowId) {
				VStack(spacing: 0) {
					// Eigener Kopf statt Default-Back-Button (Titelzeile ist versteckt).
					HStack(spacing: DS.Space.sm) {
						Button {
							dismiss()
						} label: {
							HStack(spacing: DS.Space.xs) {
								Image(systemName: "chevron.left")
								Text("Workflows")
							}
							.font(.callout)
							.foregroundStyle(DS.textSecondary)
						}
						.ghostButton()
						Spacer()
						Button {
							editing = true
						} label: {
							Image(systemName: "pencil")
						}
						.ghostButton()
						.help("Titel und Notizen bearbeiten")
						.accessibilityLabel("Bearbeiten")
						Button {
							confirmDelete = true
						} label: {
							Image(systemName: "trash")
								.foregroundStyle(DS.danger)
						}
						.ghostButton()
						.help("Workflow löschen")
						.accessibilityLabel("Löschen")
						Button("Zurücksetzen") {
							Task { await store.resetWorkflow(wf.id) }
						}
						.buttonStyle(.bordered)
					}
					.padding(.horizontal, DS.Space.xl)
					.padding(.top, DS.Space.lg)
					.padding(.bottom, DS.Space.sm)

					ScrollView {
						VStack(alignment: .leading, spacing: DS.Space.md) {
							if let err = store.workflowsError {
								ErrorBanner(message: err, retry: {
									Task { await store.loadWorkflows() }
								})
							}

							headerCard(wf)

							if !wf.notes.isEmpty {
								notesCard(wf.notes)
							}

							ForEach(Array(wf.steps.enumerated()), id: \.element.id) { idx, step in
								stepRow(workflow: wf, index: idx, step: step)
							}

							addStepRow(wf)

							if let next = wf.steps.first(where: { !$0.done }) {
								nextStepCard(next)
							} else {
								completionBanner
							}
						}
						.padding(DS.Space.xl)
						.frame(maxWidth: 640, alignment: .leading)
						.frame(maxWidth: .infinity, alignment: .topLeading)
					}
					.refreshable { await store.loadWorkflows() }
				}
				.sheet(isPresented: $editing) {
					WorkflowEditorView(workflow: wf)
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
				.confirmationDialog(
					"Schritt löschen?",
					isPresented: Binding(
						get: { stepDeleteCandidate != nil },
						set: { if !$0 { stepDeleteCandidate = nil } }
					),
					titleVisibility: .visible
				) {
					Button("Löschen", role: .destructive) {
						if let step = stepDeleteCandidate {
							stepDeleteCandidate = nil
							Task { await store.deleteStep(workflowId: wf.id, stepId: step.id) }
						}
					}
					Button("Abbrechen", role: .cancel) { stepDeleteCandidate = nil }
				} message: {
					if let step = stepDeleteCandidate {
						Text("„\(step.title)“ wird aus dem Workflow entfernt.")
					}
				}
			} else {
				EmptyStateView(
					title: "Workflow nicht gefunden",
					systemImage: "questionmark.circle",
					description: "Vielleicht wurde er gelöscht.")
			}
		}
	}

	// MARK: – Abschnitte

	/// Kopf: Titel, Fortschrittsbalken, Prozent-Chip.
	@ViewBuilder
	private func headerCard(_ wf: Workflow) -> some View {
		let isDone = wf.completedAt != nil
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			HStack(alignment: .top, spacing: DS.Space.sm) {
				Text(wf.title)
					.font(.title3.weight(.semibold))
					.foregroundStyle(DS.textPrimary)
				Spacer(minLength: DS.Space.sm)
				Chip(text: "\(Int((wf.progress * 100).rounded())) %",
				     color: isDone ? DS.success : DS.accent)
			}
			ProgressView(value: wf.progress)
				.progressViewStyle(.linear)
				.tint(isDone ? DS.success : DS.accent)
		}
		.padding(DS.Space.lg)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsCard()
	}

	/// Notizen als block-zitierte, dezente Fläche.
	@ViewBuilder
	private func notesCard(_ notes: String) -> some View {
		HStack(alignment: .top, spacing: DS.Space.md) {
			RoundedRectangle(cornerRadius: DS.Radius.pill)
				.fill(DS.border)
				.frame(width: 3)
			Text(notes)
				.font(.callout)
				.foregroundStyle(DS.textSecondary)
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.fill(DS.fillSubtle)
		)
	}

	/// Eine Schritt-Zeile: Kreis-Button, Titel (inline editierbar),
	/// bei Hover Umbenennen-/Löschen-Buttons.
	@ViewBuilder
	private func stepRow(workflow wf: Workflow, index: Int, step: WorkflowStep) -> some View {
		let isActive = step.id == wf.activeStepId && !step.done
		let isEditing = editingStepId == step.id
		HStack(spacing: DS.Space.md) {
			if isActive {
				RoundedRectangle(cornerRadius: DS.Radius.pill)
					.fill(DS.accent)
					.frame(width: 3)
			}

			Button {
				Task { await store.toggleStep(workflowId: wf.id, stepId: step.id) }
			} label: {
				Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
					.font(.title3)
					.foregroundStyle(step.done ? DS.success : DS.textTertiary)
			}
			.buttonStyle(.plain)

			if isEditing {
				TextField("Schrittstitel", text: $stepDraft)
					.font(DS.Typo.rowTitle)
					.onSubmit { commitStepRename(wf) }
				Button {
					commitStepRename(wf)
				} label: {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(DS.accent)
				}
				.buttonStyle(.plain)
				.disabled(stepDraft.trimmingCharacters(in: .whitespaces).isEmpty)
				Button {
					editingStepId = nil
				} label: {
					Image(systemName: "xmark.circle")
						.foregroundStyle(DS.textTertiary)
				}
				.buttonStyle(.plain)
			} else {
				Text("\(index + 1). \(step.title)")
					.font(DS.Typo.rowTitle)
					.strikethrough(step.done)
					.foregroundStyle(step.done ? DS.textSecondary : DS.textPrimary)

				Spacer(minLength: DS.Space.sm)

				if isActive {
					Chip(text: "Aktiv", color: DS.accent)
				}

				// Umbenennen/Löschen erscheinen erst bei Hover über der Zeile.
				if hoveredStepId == step.id {
					Button {
						editingStepId = step.id
						stepDraft = step.title
					} label: {
						Image(systemName: "pencil")
							.foregroundStyle(DS.textSecondary)
					}
					.buttonStyle(.plain)
					.help("Schritt umbenennen")
					.accessibilityLabel("Schritt umbenennen")
					Button {
						stepDeleteCandidate = step
					} label: {
						Image(systemName: "trash")
							.foregroundStyle(DS.danger)
					}
					.buttonStyle(.plain)
					.help("Schritt löschen")
					.accessibilityLabel("Schritt löschen")
				}
			}
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
				.fill(isActive ? DS.tintSoft : Color.clear)
		)
		.dsCard()
		.onHover { over in
			hoveredStepId = over ? step.id : (hoveredStepId == step.id ? nil : hoveredStepId)
		}
	}

	/// Neue Zeile unten: Feld + Plus-Button (Enter speichert direkt).
	@ViewBuilder
	private func addStepRow(_ wf: Workflow) -> some View {
		HStack(spacing: DS.Space.sm) {
			TextField("Neuen Schritt hinzufügen …", text: $newStepTitle)
				.font(.callout)
				.onSubmit { addStep(wf) }
			Button {
				addStep(wf)
			} label: {
				if stepBusy {
					ProgressView().controlSize(.small)
				} else {
					Image(systemName: "plus.circle.fill")
						.font(.title3)
						.foregroundStyle(DS.accent)
				}
			}
			.buttonStyle(.plain)
			.disabled(stepBusy
				|| newStepTitle.trimmingCharacters(in: .whitespaces).isEmpty)
			.help("Schritt hinzufügen")
			.accessibilityLabel("Schritt hinzufügen")
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.overlay(
			RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
				.strokeBorder(DS.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
		)
	}

	/// Hervorgehobener nächster offener Schritt.
	@ViewBuilder
	private func nextStepCard(_ step: WorkflowStep) -> some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "arrow.right.circle.fill")
				.foregroundStyle(DS.accent)
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text("Als Nächstes")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textSecondary)
				Text(step.title)
					.font(DS.Typo.rowTitle)
					.foregroundStyle(DS.textPrimary)
			}
			Spacer(minLength: DS.Space.sm)
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
				.fill(DS.tintSoft)
		)
		.dsCard()
	}

	/// Grüner Abschluss-Banner, wenn alle Schritte erledigt sind.
	private var completionBanner: some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "checkmark.seal.fill")
				.foregroundStyle(DS.success)
			Text("Komplett erledigt")
				.font(.callout.weight(.semibold))
				.foregroundStyle(DS.success)
			Spacer(minLength: DS.Space.sm)
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.fill(DS.success.opacity(0.10))
		)
		.overlay(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.strokeBorder(DS.success.opacity(0.35), lineWidth: 1)
		)
	}

	// MARK: – Schritt-Aktionen

	private func commitStepRename(_ wf: Workflow) {
		let trimmed = stepDraft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		let stepId = editingStepId
		editingStepId = nil
		guard let stepId,
		      wf.steps.first(where: { $0.id == stepId })?.title != trimmed else { return }
		Task { await store.renameStep(workflowId: wf.id, stepId: stepId, title: trimmed) }
	}

	private func addStep(_ wf: Workflow) {
		let trimmed = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !stepBusy else { return }
		stepBusy = true
		newStepTitle = ""
		Task {
			await store.addStep(workflowId: wf.id, title: trimmed)
			stepBusy = false
		}
	}
}
