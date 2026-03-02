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
        uiView.drawing = drawing
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

        init(_ parent: CanvasView) {
            self.parent = parent
            super.init()
            observer = try? DittoManager.shared?.ditto?.store.registerObserver(query: "SELECT * FROM drawings", handler: updateFromDitto(_:))
        }

        deinit {
            observer?.cancel()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard canvasView.drawing != parent.drawing else {
                print("skipping redundant insert")
                return
            }
            guard let jsonData = try? JSONEncoder().encode(canvasView.drawing),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
//            guard let drawingString = String(data: canvasView.drawing.dataRepresentation(), encoding: .utf8) else { return }
            print("insert")
            Task {
                do {
                    try await DittoManager.shared?.ditto?.store.execute(query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                                                                        arguments: ["doc": ["_id": "1","drawing": jsonString]]) // TODO ID from somewhere
                } catch let error {
                    print(error)
                }
            }
        }

        func updateFromDitto(_ result: DittoSwift.DittoQueryResult) {
            print(result.items.count)
            guard let item = result.items.first,
            let drawingJSONString = item.value["drawing"] as? String,
            let drawingJSONData = drawingJSONString.data(using: .utf8),
                let drawing = try? JSONDecoder().decode(PKDrawing.self, from: drawingJSONData) else { return }

            guard drawing != parent.drawing else {
                print("skipping redundant observation")
                return
            }
            print("observe")
            parent.drawing = drawing // TODO merge, use PKStrokes for granular updates etc
        }
    }

}
