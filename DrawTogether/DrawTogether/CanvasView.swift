//
//  CanvasView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit
import DittoSwift

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var toolPicker: PKToolPicker?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput // Allows drawing with finger or Apple Pencil
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        context.coordinator.toolPicker = toolPicker
        toolPicker?.setVisible(true, forFirstResponder: uiView)
        toolPicker?.addObserver(uiView)
        uiView.becomeFirstResponder() // Make canvas view the first responder to show tool picker
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        var toolPicker: PKToolPicker?
        var observer: DittoStoreObserver?
        var model = DittoDrawingModel()
        var isUpdatingFromDitto = false

        init(_ parent: CanvasView) {
            self.parent = parent
            super.init()
            observer = try? DittoManager.shared?.ditto?.store.registerObserver(query: "SELECT * FROM drawings", handler: updateFromDitto(_:))
        }

        deinit {
            observer?.cancel()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromDitto else { return }

            let (inserts, removes) = model.diff(currentStrokes: canvasView.drawing.strokes)
            guard !inserts.isEmpty || !removes.isEmpty else { return }

            let drawingID = model.drawingID
            Task {
                do {
                    guard let ditto = DittoManager.shared?.ditto else { return }

                    try await ditto.store.transaction { transaction in
                        // Batch all inserts into a single MERGE operation
                        if !inserts.isEmpty {
                            let doc: [String: Any] = ["_id": drawingID, "strokes": inserts]
                            try await transaction.execute(
                                query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                                arguments: ["doc": doc]
                            )
                        }

                        for key in removes {
                            try await transaction.execute(
                                query: "UPDATE drawings UNSET strokes[:strokeKey] WHERE _id = :drawingID",
                                arguments: ["drawingID": drawingID, "strokeKey": key]
                            )
                        }

                        return .commit
                    }

                    // Apply local state only after transaction commits successfully
                    await MainActor.run {
                        self.model.apply(inserts: inserts, removes: removes)
                    }
                } catch {
                    print("Error syncing strokes: \(error)")
                }
            }
        }

        func updateFromDitto(_ result: DittoSwift.DittoQueryResult) {
            guard let item = result.items.first(where: { ($0.value["_id"] as? String) == model.drawingID }),
                  let rawMap = item.value["strokes"] as? [String: Any] else {
                return
            }

            var strokesMap: [String: String] = [:]
            for (key, value) in rawMap {
                if let strokeString = value as? String {
                    strokesMap[key] = strokeString
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.model.updateFromStrokesMap(strokesMap)
                self.isUpdatingFromDitto = true
                self.parent.drawing = self.model.drawing()
                self.isUpdatingFromDitto = false
            }
        }
    }
}
