# Brain Dump

Brain Dump is a native Mac app for capturing raw fragments of thought and turning them into useful context over time.

It is built around a simple idea: people save things before they know what those things mean. Brain Dump lets you capture first, then helps patterns, themes, and ideas emerge later from the evidence you have already saved.

## What It Does

- Captures text snippets, URLs, screenshots, images, notes, complaints, references, and half-formed ideas.
- Stores raw fragments locally first, so capture stays fast and reliable.
- Processes saved fragments in the background.
- Summarizes and connects related ideas over time.
- Surfaces durable themes only when there is enough supporting evidence.

## Product Direction

Brain Dump is not a browser-extension-first product, chatbot-first notes app, task manager, or generic knowledge base. It is a calm native Mac utility that works like a personal memory layer.

The app is designed around:

- Instant capture.
- Local-first storage.
- Explainable AI output.
- Sparse, useful resurfacing.
- Native macOS workflows.

The intended experience is simple: dump fragments as they happen, then let Brain Dump show you what keeps coming back.

## Status

This project is in early product and implementation work. The current focus is the native Mac app foundation, capture flows, local storage model, and evidence-backed synthesis pipeline.

## Development

This repository is organized as a Swift package for the macOS application and supporting modules.

```sh
swift build
swift test
```

## License

License information has not been published yet.
