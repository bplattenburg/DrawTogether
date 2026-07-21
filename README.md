# DrawTogether
A Ditto-backed app for collaborative drawing, based on Apple's PencilKit.

This is a "just for fun" side project that I thought would be a lot easier than it turned out to be - PencilKit makes a lot of single-write assumptions and optimizations - which turned this into a really interesting (if complicated) case study in utilizing Ditto's CRDT-based deterministic conflict resolution with multiple writers. 

To learn more about Ditto, see the docs [here](https://docs.ditto.live/).

To learn more about PencilKit, see the docs [here](https://developer.apple.com/documentation/pencilkit).

To run the app, copy `.env.example` to `.env` and fill in the Ditto database ID, server URL, and playground token. The Xcode build generates `Env.swift` from that local file.

This is open source so feel free to contribute if you want!
