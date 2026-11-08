import SwiftUI

/// Workflow-Liste mit Fortschritt; Detailansicht = Fokus-Modus der Web-App.
struct WorkflowsView: View {
	@Environment(AppStore.self) private var store

	var body: some View {
		NavigationStack {
			Group {
				if store.workflowsBusy && store.workflows.isEmpty {
					TimelineSkeleton()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if store.workflows.isEmpty {
					EmptyStateView(
						title: "Keine Workflows",
						systemImage: "checklist",
						description: store.workflowsError ?? "Legt die Web-App an – die App zeigt sie hier.")
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
								}
								.buttonStyle(.plain)
							}
						}
						.padding(DS.Space.xl)
						.frame(maxWidth: 640, alignment: .leading)
						.frame(maxWidth: .infinity, alignment: .topLeading)
					}
					.navigationDestination(for: String.self) { id in
						WorkflowDetailView(workflowId: id)
					}
				}
			}
			.navigationTitle("Workflows")
			.refreshable { await store.loadWorkflows() }
		}
		.task {
			if store.workflows.isEmpty { await store.loadWorkflows() }
		}
	}
}

// MARK: – Workflow-Karte (Liste)

/// Karte in der Workflow-Liste: Titel, linearer Fortschritt, Zähler, Erledigt-Chip.
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
				.tint(workflow.completedAt != nil ? DS.success : Color.accentColor)

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
				.fill(Color.primary.opacity(hovering ? 0.045 : 0))
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
	}
}

// MARK: – Detail (Fokus-Modus)

struct WorkflowDetailView: View {
	@Environment(AppStore.self) private var store
	let workflowId: String

	var body: some View {
		Group {
			if let wf = store.workflow(workflowId) {
				ScrollView {
					VStack(alignment: .leading, spacing: DS.Space.md) {
						headerCard(wf)

						if !wf.notes.isEmpty {
							notesCard(wf.notes)
						}

						ForEach(Array(wf.steps.enumerated()), id: \.element.id) { idx, step in
							stepRow(workflow: wf, index: idx, step: step)
						}

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
				.navigationTitle(wf.title)
				.toolbar {
					ToolbarItem(placement: .automatic) {
						Button("Zurücksetzen") {
							Task { await store.resetWorkflow(wf.id) }
						}
					}
				}
			} else {
				EmptyStateView(
					title: "Workflow nicht gefunden",
					systemImage: "questionmark.circle",
					description: "Vielleicht wurde er in der Web-App gelöscht.")
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
				     color: isDone ? DS.success : Color.accentColor)
			}
			ProgressView(value: wf.progress)
				.progressViewStyle(.linear)
				.tint(isDone ? DS.success : Color.accentColor)
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

	/// Eine Schritt-Zeile: Kreis-Button, Titel, Aktiv-Markierung.
	@ViewBuilder
	private func stepRow(workflow wf: Workflow, index: Int, step: WorkflowStep) -> some View {
		let isActive = step.id == wf.activeStepId && !step.done
		HStack(spacing: DS.Space.md) {
			if isActive {
				RoundedRectangle(cornerRadius: DS.Radius.pill)
					.fill(Color.accentColor)
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

			Text("\(index + 1). \(step.title)")
				.font(DS.Typo.rowTitle)
				.strikethrough(step.done)
				.foregroundStyle(step.done ? DS.textSecondary : DS.textPrimary)

			Spacer(minLength: DS.Space.sm)

			if isActive {
				Chip(text: "Aktiv", color: Color.accentColor)
			}
		}
		.padding(DS.Space.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
				.fill(isActive ? DS.tintSoft : Color.clear)
		)
		.dsCard()
	}

	/// Hervorgehobener nächster offener Schritt.
	@ViewBuilder
	private func nextStepCard(_ step: WorkflowStep) -> some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "arrow.right.circle.fill")
				.foregroundStyle(Color.accentColor)
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
}
