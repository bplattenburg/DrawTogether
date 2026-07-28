# DrawTogether

DrawTogether is a collaborative iOS drawing app built with
[PencilKit](https://developer.apple.com/documentation/pencilkit) and
[Ditto](https://docs.ditto.live/). Each device writes to its
[local Ditto store](https://docs.ditto.live/key-concepts/accessing-data), and
Ditto syncs those changes when the devices can communicate.

PencilKit represents a canvas as one `PKDrawing` designed for a single editing
session. Collaborative drawing needs conflict resolution below the complete
drawing, so DrawTogether uses the individual stroke as that boundary.

## Data model

Storing a serialized `PKDrawing` in one field would make the entire canvas one
last-write-wins value. Separate strokes created concurrently would compete as
complete drawing updates. DrawTogether uses one
[Ditto document](https://docs.ditto.live/key-concepts/document-model) per drawing
and stores each stroke in a map:

```json
{
  "_id": "drawing-1",
  "name": "Design notes",
  "strokes": {
    "2026-03-25T16:20:14.127Z": "<base64 PKDrawing>",
    "2026-03-25T16:20:16.842Z": "<base64 PKDrawing>"
  }
}
```

`strokes` is an
[add-wins Ditto map](https://docs.ditto.live/dql/types-and-definitions#map-operations).
Each key merges independently, so concurrent additions from different peers are
preserved. The base64 value under each key is a
[register](https://docs.ditto.live/dql/types-and-definitions#register-operations),
which moves the last-write-wins boundary from the whole canvas down to one
stroke.

For example:

```text
Peer 1 adds stroke A            Peer 2 adds stroke B
strokes["...14.127Z"] = A       strokes["...16.842Z"] = B

                         sync
                          │
                          ▼
             strokes = { A, B }
```

The peers can receive those operations in either order and still converge on
both strokes. If both peers change the same stroke, Ditto deterministically
selects one complete encoded version. No separate conflict resolver is needed;
the document shape defines the merge behavior.

This follows Ditto's
[map-keyed collection pattern](https://docs.ditto.live/best-practices/conflict-resolution-patterns).
Ditto's [Syncing Data](https://docs.ditto.live/key-concepts/syncing-data)
documentation explains the add-wins map and last-write-wins register behavior
used here.

## PencilKit serialization

Each map key comes from `PKStrokePath.creationDate`. Its ISO 8601 representation
is stable and sortable, so the same value provides stroke identity and z-order
when rebuilding the canvas.

Each map value uses PencilKit's native `PKDrawing.dataRepresentation()` encoded
as base64. It normally contains one `PKStroke`, so the app keeps PencilKit's ink,
path, transform, and eraser mask without maintaining another vector format.

PencilKit's bitmap eraser can change a stroke's mask or split one stroke into
several pieces. Those pieces keep the original creation date, so DrawTogether
groups them under the same Ditto key and encodes them together. A fingerprint
detects mask and split changes while letting unchanged groups reuse their
existing encoding.

## Synchronization

`DrawingSyncCoordinator` is the bridge between `PKCanvasView` and the Ditto
document:

1. It debounces canvas callbacks for 100 milliseconds.
2. `DittoDrawingModel` groups the current strokes by creation date and compares
   them with the last synchronized state.
3. It writes new and changed entries with `ON ID CONFLICT DO
   UPDATE_LOCAL_DIFF`, and explicitly `UNSET`s removed entries in the same
   [transaction](https://docs.ditto.live/sdk/latest/crud/transactions).
4. A Ditto store observer receives the local or remote document, decodes the
   entries, sorts the keys, and rebuilds the `PKDrawing`.

[`UPDATE_LOCAL_DIFF`](https://docs.ditto.live/dql/insert#do-update-local-diff)
means the coordinator can submit its current stroke map without rewriting and
replicating values that did not change.
[`UNSET`](https://docs.ditto.live/dql/update#deleting-fields) tells Ditto that an
omitted stroke was intentionally removed.

The app uses a
[sync subscription](https://docs.ditto.live/sdk/latest/sync/syncing-data) for
the `drawings` collection and a separate
[store observer](https://docs.ditto.live/sdk/latest/crud/observing-data-changes)
for each open drawing. The subscription brings documents into the local store.
The observer turns changes in that store back into UI state.

## Implementation

- [`DrawingSyncCoordinator.swift`](DrawTogether/DrawTogether/Drawing/DrawingSyncCoordinator.swift)
  owns the PencilKit-to-Ditto sync loop.
- [`DittoDrawingModel.swift`](DrawTogether/DrawTogether/Drawing/DittoDrawingModel.swift)
  calculates map updates and rebuilds a drawing.
- [`DittoStrokeModel.swift`](DrawTogether/DrawTogether/Drawing/DittoStrokeModel.swift)
  handles encoding, grouping, fingerprints, and keys.
- [`DrawTogetherTests`](DrawTogether/DrawTogetherTests) covers round trips,
  eraser splits, removals, observers, and DQL transactions against local Ditto
  instances.

## Configuration

Copy `.env.example` to `.env`, fill in the Ditto database ID, server URL, and
playground token, then open `DrawTogether/DrawTogether.xcodeproj`. The build
generates an ignored `Env.swift` from that local file.
