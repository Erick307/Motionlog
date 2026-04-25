//
//  DashboardView.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {

    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Form {
                timestampsSection
                exportSection
            }
            .navigationTitle("MotionLog")
            // Start collecting as soon as the view appears.
            // The modifier cancels the task automatically when the view disappears.
            .task { await viewModel.startCollection() }
            // Share sheet
            .sheet(isPresented: $viewModel.showExportSheet, onDismiss: cleanupExportFile) {
                if let url = viewModel.exportFileURL {
                    ActivityView(items: [url])
                }
            }
            // No-new-data alert
            .alert("No New Data", isPresented: $viewModel.showNoDataAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There are no new readings since your last export.")
            }
        }
    }

    // MARK: Sections

    private var timestampsSection: some View {
        Section {
            TimestampRow(label: "First Collection", date: viewModel.firstCollectionTime)
            TimestampRow(label: "Last Collection",  date: viewModel.lastCollectionTime)
            TimestampRow(label: "Last Export",      date: viewModel.lastExportTime)
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await viewModel.exportData() }
            } label: {
                Label("Export & Share CSV", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    // MARK: Helpers

    /// Deletes the temp CSV file once the share sheet is dismissed.
    private func cleanupExportFile() {
        if let url = viewModel.exportFileURL {
            try? FileManager.default.removeItem(at: url)
            viewModel.exportFileURL = nil
        }
    }
}

// MARK: - TimestampRow

/// Displays a labelled date, falling back to "Never" when the date is nil.
private struct TimestampRow: View {

    let label: String
    let date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(date.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Never")
                .font(.body)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ActivityView

/// Thin `UIViewControllerRepresentable` wrapper around `UIActivityViewController`.
struct ActivityView: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#Preview("With data") {
    DashboardView()
}

#Preview("Empty state") {
    DashboardView()
}
