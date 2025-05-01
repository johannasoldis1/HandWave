//
//  DataView.swift
//  HandWave
//

import SwiftUI

struct DataView: View {
    @State private var recordedFiles: [String] = []

    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(destination: PlotView()) {
                    Text("Go to Plot Screen")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.bottom, 20)

                List(recordedFiles, id: \.self) { fileName in
                    NavigationLink(destination: PlotView(initialFile: fileName)) {
                        HStack {
                            Text(fileName)
                                .lineLimit(1)
                                .padding(.trailing, 10)

                            Spacer()

                            // Export Button
                            Button(action: {
                                exportCSV(fileName)
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .frame(minWidth: 80)
                                .padding(8)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Delete Button
                            Button(action: {
                                deleteCSV(fileName)
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                                .frame(minWidth: 80)
                                .padding(8)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 5)
                    }
                }
                .onAppear {
                    loadCSVFiles()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EMG Data")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // Function to Load Recorded CSV Files
    func loadCSVFiles() {
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: documentDirectory.path)
                recordedFiles = files.filter { $0.hasSuffix(".csv") }
            } catch {
                print("Error loading CSV files: \(error)")
            }
        }
    }

    // Function to Export a Selected CSV File
    func exportCSV(_ fileName: String) {
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentDirectory.appendingPathComponent(fileName)

            let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityController, animated: true, completion: nil)
            }
        }
    }

    // Function to Delete a Selected CSV File
    func deleteCSV(_ fileName: String) {
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentDirectory.appendingPathComponent(fileName)
            do {
                try fileManager.removeItem(at: fileURL)
                loadCSVFiles()
            } catch {
                print("Error deleting CSV file: \(error)")
            }
        }
    }
}

