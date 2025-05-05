//
//  PlotView.swift
//  HandWave
//

import SwiftUI
import Charts // Make sure to import Charts framework (Swift Charts)
import UniformTypeIdentifiers // my add
import UIKit


struct DataPoint: Identifiable {
    var id = UUID()
    var time: Double
    var value: Double
}

// my add variable for the percentile chart
struct EffortZone: Identifiable {
    var id = UUID()
    var label: String
    var percentage: Double
}

struct PlotView: View {
    @State private var recordedFiles: [String] = []
    var initialFile: String? = nil
    @State private var selectedFile: String = "" // myline
    @State private var dataPoints: [DataPoint] = []
    @State private var effortZones: [EffortZone] = [] // array for effort zones
    @State private var showingImporter = false  // my line to import csv file
    @State private var showExportAlert = false// alert of photo
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case pdf = "PDF"
        var id: String { rawValue }
    }

    @State private var exportFormat: ExportFormat = .png
    
    

    var body: some View {
        VStack {
            HStack(spacing: 16) {
                Button("Import CSV File") {
                    showingImporter = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Export Chart") {
                    // 1. Build the export view
                    let exportView = VStack(spacing: 20) {
                        // Title
                        Text("Percentage (%MVE)")
                            .font(.headline)

                        // Line Chart
                        Chart {
                            ForEach(dataPoints) { point in
                                LineMark(
                                    x: .value("Time (s)", point.time),
                                    y: .value("%MVE", point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.blue)
                            }

                            RuleMark(y: .value("%MVE", 10))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                                .foregroundStyle(.red)

                            RuleMark(y: .value("%MVE", 30))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                                .foregroundStyle(.green)
                        }
                        .chartXScale(domain: 0...(dataPoints.last?.time ?? 60))
                        .chartYScale(domain: 0...110)
                        .chartXAxis {
                            AxisMarks(position: .bottom, values: .stride(by: 5)) {
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: [0, 10, 20, 30, 40, 60, 80, 100]) { value in
                                AxisGridLine()
                                AxisTick()
                                if let val = value.as(Double.self) {
                                    if val == 10 {
                                        AxisValueLabel {
                                            Text("10%")
                                                .foregroundColor(.red)
                                                .font(.caption2)
                                        }
                                    } else if val == 30 {
                                        AxisValueLabel {
                                            Text("30%")
                                                .foregroundColor(.green)
                                                .font(.caption2)
                                        }
                                    } else {
                                        AxisValueLabel()
                                    }
                                }
                            }
                        }
                        .frame(width: 700, height: 300)

                        // X Axis Label
                        Text("Time (s)")
                            .font(.caption)
                            .padding(.top, -6)

                        // Pie Chart
                        if !effortZones.isEmpty {
                            VStack {
                                Text("Effort Zone Distribution")
                                    .font(.headline)

                                Chart(effortZones) { zone in
                                    SectorMark(
                                        angle: .value("Proportion", zone.percentage),
                                        innerRadius: .ratio(0.0),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(by: .value("Zone", zone.label))
                                    .annotation(position: .overlay) {
                                        Text("\(zone.label)\n\(String(format: "%.1f", zone.percentage))%")
                                            .font(.caption2)
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 300, height: 200)
                                .chartLegend(position: .bottom, alignment: .center)
                            }
                        }

                        // Watermark
                        HStack {
                            Spacer()
                            Text("Hand Wave • Exported \(currentDateString())")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .environment(\.colorScheme, .light)

                    // 2. Render the chart to image
                    let chartImage = renderChartAsImage(
                        view: exportView,
                        size: CGSize(width: 720, height: 720)
                    )

                    // 3. Save as PNG with date-based filename
                    let filename = "mve_chart_\(currentDateString()).png"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

                    if let imageData = chartImage.pngData() {
                        do {
                            try imageData.write(to: tempURL)
                            ShareSheet(items: [tempURL]).present()
                        } catch {
                            print("❌ Failed to write image: \(error)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                    .sheet(isPresented: $showShareSheet) {
                        if let image = shareImage {
                            ShareSheet(items: [image])
                        }
                    }
                }
                .padding(.top)
                .onChange(of: shareImage) { oldValue, newValue in
                    if newValue != nil {
                        showShareSheet = true
                    }
                }
                
            
            // my add
            if recordedFiles.isEmpty {
                Text("No CSV files found")
                    .font(.headline)
                    .padding()
            } else {
                // Picker to select CSV file
                Picker("Select File", selection: $selectedFile) {
                    ForEach(recordedFiles, id: \.self) { file in
                        Text(file)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                
                if dataPoints.isEmpty {
                    Text("No data loaded yet")
                        .font(.headline)
                        .padding()
                } else {
                    HStack(alignment: .center) {
                        // Y Axis Label
                        Text("Percentage (%MVE)")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: 25, height: 200, alignment: .top)
                            .offset(x: 10, y: 70)
                        
                        VStack(spacing: 4) {
                            Chart {
                                ForEach(dataPoints) { point in
                                    LineMark(
                                        x: .value("Time (s)", point.time),
                                        y: .value("%MVE", point.value)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(.blue)
                                }
                                
                                // Threshold line at 10%
                                RuleMark(y: .value("%MVE", 10))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                                    .foregroundStyle(.red)
                                
                                // Threshold line at 30%
                                RuleMark(y: .value("%MVE", 30))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                                    .foregroundStyle(.green)
                            }
                            .chartXScale(domain: 0...(dataPoints.last?.time ?? 60))
                            .chartScrollableAxes(.horizontal)
                            .chartXAxis {
                                AxisMarks()
                            }
                            .chartYScale(domain: 0...110)
                            .chartYAxis {
                                AxisMarks(position: .leading, values: [0, 10, 20, 30, 40, 60, 80, 100]) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    
                                    if let val = value.as(Double.self) {
                                        if val == 10 {
                                            AxisValueLabel {
                                                Text("10%")
                                                    .foregroundColor(.red)
                                                    .font(.caption)
                                            }
                                        } else if val == 30 {
                                            AxisValueLabel {
                                                Text("30%")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                            }
                                        } else {
                                            AxisValueLabel()
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                            
                            // X Axis Label
                            Text("Time (s)")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        }
                        
                    }
                    .padding(.horizontal, 16) // only right side now
                    
                    // Pie Chart for Effort Zones to test
                    if !effortZones.isEmpty {
                        Text("Effort Zone Distribution over Time")
                            .font(.subheadline)
                            .padding(.top, 12)
                        
                        Chart(effortZones) { zone in
                            SectorMark(
                                angle: .value("Proportion", zone.percentage),
                                innerRadius: .ratio(0.0),
                                angularInset: 1
                            )
                            .foregroundStyle(by: .value("Zone", zone.label))
                            .annotation(position: .overlay) {
                                Text("\(zone.label)\n\(String(format: "%.1f", zone.percentage))%")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 200)
                        .chartLegend(position: .bottom, alignment: .center)
                        .padding(.horizontal)
                    }
                }
            }
            
            Spacer()
        }
        .navigationTitle("Plotting Results")
        .font(.subheadline)
        .padding(.top, 12)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EmptyView() // Hides HandWave logo
            }
        }
        .sheet(isPresented: $showingImporter) {
            DocumentPicker { url in
                let fileName = url.lastPathComponent
                copyCSVIntoApp(url: url)

                // Wait for copy, then load it directly (no need to wait for list to update)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedFile = fileName
                    loadDataFromCSV(fileName: fileName)

                    if !recordedFiles.contains(fileName) {
                        recordedFiles.append(fileName)
                    }
                }
            }
        }
        .onAppear {
            loadCSVFiles()
            if let file = initialFile {
                print("Initial file selected: \(file)")
                selectedFile = file
                loadDataFromCSV(fileName: file)
            }
        }
        .alert("Chart Saved ✅", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The chart image was successfully saved to your Photos.")
        }
    }
    
    // Load available CSV files
    func loadCSVFiles() {
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: documentDirectory.path)
                recordedFiles = files.filter { $0.hasSuffix(".csv") }

                if let firstFile = recordedFiles.first {
                    self.selectedFile = firstFile //  sync selection
                    loadDataFromCSV(fileName: firstFile)
                }
            } catch {
                print("Error loading CSV files: \(error)")
            }
        }
    }

    // Load Data from CSV
    func loadDataFromCSV(fileName: String) {
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentDirectory.appendingPathComponent(fileName)

            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let rows = content.components(separatedBy: "\n")

                var points: [DataPoint] = []
                var baseTime: Double? = nil

                for row in rows {
                    let columns = row.components(separatedBy: ",")
                    if columns.count >= 6,
                       let timestamp = Double(columns[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                       let mve = Double(columns[5].trimmingCharacters(in: .whitespacesAndNewlines)) {

                        // Normalize timestamps to start at zero
                        if baseTime == nil {
                            baseTime = timestamp
                        }
                        let relativeTime = timestamp - (baseTime ?? 0)

                        points.append(DataPoint(time: relativeTime, value: mve))
                    }
                }

                self.dataPoints = points

                // Calculate effort zone percentages
                let total = max(points.count, 1)
                let rest = points.filter { $0.value < 10 }.count
                let light = points.filter { $0.value >= 10 && $0.value < 30 }.count
                let high = points.filter { $0.value >= 30 }.count

                self.effortZones = [
                    EffortZone(label: "Low(<10%)", percentage: Double(rest) * 100.0 / Double(total)),
                    EffortZone(label: "Moderate(10–30%)", percentage: Double(light) * 100.0 / Double(total)),
                    EffortZone(label: "High(>50%)", percentage: Double(high) * 100.0 / Double(total))
                ]
                    
            } catch {
                print("Error reading CSV file: \(error)")
            }
        }
    }

    // from here is a test to try to uppload the csv file on the simulator. can be removed
    // CSV Importer
    func copyCSVIntoApp(url: URL) {
        let fileManager = FileManager.default
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Could not access file securely.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let destinationURL = documentDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: url, to: destinationURL)
                print("✅ Successfully copied: \(url.lastPathComponent)")
            } catch {
                print("❌ Error copying file: \(error)")
            }
        }
    }
}

// File Import Picker
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.commaSeparatedText])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first {
                parent.onPick(first)
            }
        }
    }
}



struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    private var activityVC: UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    // ✅ Working present() method without Context()
    func present() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}


func currentDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}


func renderChartAsImage<V: View>(view: V, size: CGSize) -> UIImage {
    let controller = UIHostingController(rootView: view)
    controller.view.bounds = CGRect(origin: .zero, size: size)
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { context in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }
}
