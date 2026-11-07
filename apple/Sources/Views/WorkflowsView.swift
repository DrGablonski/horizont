import SwiftUI

/// Workflow-Liste mit Fortschritt; Detailansicht = Fokus-Modus der Web-App.
struct WorkflowsView: View {
	@Environment(AppStore.self) private var store

	var body: some View {
		NavigationStack {
			Group {
				if store.workflowsBusy && store.workflows.isEmpty {
					ProgressView("Lade Workflows …")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if store.workflows.isEmpty {
					ContentUnavailableView(
						"Keine Workflows",
						systemImage: "checklist",
						description: Text(store.workflowsError ?? "Legt die Web-App an – die App zeigt sie hier."))
				} else {
					List(store.workflows) { wf in
						NavigationLink(value: wf.id) {
							VStack(alignment: .leading, spacing: 6) {
								Text(wf.title).font(.headline)
								ProgressView(value: wf.progress)
									.progressViewStyle(.linear)
								HStack {
									Text("\(wf.steps.filter(\.done).count)/\(wf.steps.count) Schritte")
										.font(.caption)
										.foregroundStyle(.secondary)
									if wf.completedAt != nil {
										Text("· erledigt").font(.caption).foregroundStyle(.green)
									}
								}
							}
							.padding(.vertical, 4)
						}
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

struct WorkflowDetailView: View {
	@Environment(AppStore.self) private var store
	let workflowId: String

	var body: some View {
		Group {
			if let wf = store.workflow(workflowId) {
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						if !wf.notes.isEmpty {
							Text(wf.notes)
								.foregroundStyle(.secondary)
						}

						ForEach(Array(wf.steps.enumerated()), id: \.element.id) { idx, step in
							HStack(spacing: 12) {
								Button {
									Task { await store.toggleStep(workflowId: wf.id, stepId: step.id) }
								} label: {
									Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
										.font(.title3)
										.foregroundStyle(step.done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
								}
								.buttonStyle(.plain)

								VStack(alignment: .leading, spacing: 2) {
									Text("\(idx + 1). \(step.title)")
										.font(step.id == wf.activeStepId ? .body.weight(.semibold) : .body)
										.strikethrough(step.done)
										.foregroundStyle(step.done ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .labelColor))
									if step.id == wf.activeStepId && !step.done {
										Text("Aktueller Schritt")
											.font(.caption2)
											.foregroundStyle(Color.accentColor)
									}
								}
								Spacer()
							}
							.padding(10)
							.background(
								RoundedRectangle(cornerRadius: 10)
									.fill(step.id == wf.activeStepId && !step.done
									      ? Color.accentColor.opacity(0.12)
									      : Color(nsColor: .quaternaryLabelColor).opacity(0.35))
							)
						}

						if let next = wf.steps.first(where: { !$0.done }) {
							Text("Als Nächstes: \(next.title)")
								.font(.callout)
								.foregroundStyle(.secondary)
						} else {
							Label("Komplett erledigt", systemImage: "checkmark.seal.fill")
								.foregroundStyle(.green)
						}
					}
					.padding()
					.frame(maxWidth: 640, alignment: .leading)
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
				ContentUnavailableView("Workflow nicht gefunden", systemImage: "questionmark.circle")
			}
		}
	}
}
