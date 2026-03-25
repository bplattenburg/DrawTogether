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

            model.apply(inserts: inserts, removes: removes)

            let drawingID = model.drawingID
            Task {
                do {
                    guard let ditto = DittoManager.shared?.ditto else { return }

                    try await ditto.store.transaction { transaction in
                        for (key, jsonString) in inserts {
                            let doc: [String: Any] = ["_id": drawingID, "strokes": [key: jsonString]]
                            try await transaction.execute(
                                query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                                arguments: ["doc": doc]
                            )
                        }

                        for key in removes {
                            try await transaction.execute(
                                query: "UPDATE drawings UNSET strokes.\(key) WHERE _id = :drawingID",
                                arguments: ["drawingID": drawingID]
                            )
                        }

                        return .commit
                    }
                } catch {
                    print("Error syncing strokes: \(error)")
                }
            }
        }

        func updateFromDitto(_ result: DittoSwift.DittoQueryResult) {
            // Parse the strokes MAP from the Ditto result
            var strokesMap: [String: String] = [:]
            if let item = result.items.first,
               let rawMap = item.value["strokes"] as? [String: Any] {
                for (key, value) in rawMap {
                    if let strokeString = value as? String {
                        strokesMap[key] = strokeString
                    }
                }
            }

            model.updateFromStrokesMap(strokesMap)
            isUpdatingFromDitto = true
            parent.drawing = model.drawing()
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromDitto = false
            }
        }
    }
}
