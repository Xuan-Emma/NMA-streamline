# NMA Streamline

A native **macOS application** built in **Swift 6 / SwiftUI** that automates the front-end of **Network Meta-Analysis (NMA)**: intelligent screening, deduplication, and PRISMA-compliant workflow management.

---

## Features

### 1. Data Architecture (SwiftData)
- **Hierarchical model**: `NMAProject → Study → Citation / Outcome / ReviewerDecision`
- Full audit trail: every record tracks its `Source`, `Status`, and `ExclusionReason`
- `Outcome` entity distinguishes **Primary**, **Secondary**, and **Linker** outcomes
- Multi-report linking: multiple citations (e.g., conference poster + main paper) can be attached to one parent `Study`

### 2. Import & Deduplication Engine
| Format | Parser |
|--------|--------|
| `.ris` | `RISParser` — full RIS tag coverage |
| `.bib` | `BibParser` — handles nested `{}` and `""` quoting |
| PubMed `.xml` | `PubMedXMLParser` — streams `PubmedArticleSet` |

**Multi-pass deduplication** (`DeduplicationEngine` actor):
- **Pass 1**: Exact match on DOI, PMID, NCT ID
- **Pass 2**: Weighted Levenshtein fuzzy match on Title (60%) + Year (20%) + First Author (20%) at a configurable ≥ 85% threshold (adjustable via `DeduplicationEngine.fuzzyThreshold`)

**Merge Workspace** (`MergeWorkspaceView`): side-by-side comparison with *Merge into Primary* / *Discard Duplicate* / *Keep Both* actions.

### 3. Intelligent Screening Workflow
- **Dual-review** support with configurable **Blind Mode** (decisions hidden until both reviewers decide)
- **Conflict Resolution** view triggered automatically on disagreement
- **Keyboard-first navigation**: `J` Include · `K` Exclude · `L` Maybe · `U` Undo
- **Pre-fetching cache**: next 10 abstracts are AI-analyzed in the background for zero-latency transitions

### 4. Local AI Assistant
Protocol-based design (`AIAssistantProtocol`) with two implementations:

| Class | Description |
|-------|-------------|
| `RuleBasedAIAssistant` | Fast, offline keyword-matching engine — always available |
| `CoreMLAIAssistant` | Stub for CoreML / MLX-Swift LLM (Llama 3 / Mistral) — activate by bundling an `.mlmodelc` |

**AI capabilities:**
- **PICO Check**: flags abstract against user-defined Population / Intervention / Comparator / Outcome / Study-Design criteria
- **Outcome Extraction**: detects clinical endpoints in the abstract
- **Linker Identification**: flags outcomes that could serve as network connectors
- **Ghost UI**: AI suggestions appear as non-binding hint tags — the human reviewer always decides

### 5. PRISMA 2020 Compliance
- Real-time **PRISMA 2020 flow diagram** (`PRISMAFlowView`) generated from live SwiftData counts
- **Forced exclusion reason** selection at the Full-Text stage (PRISMA-N requirement)
- Full exclusion-reason breakdown table

### 6. Network Geometry Preview
- Live **node-and-edge network plot** (`NetworkGeometryView`) built with a spring-layout algorithm
- Nodes sized by degree (number of comparisons)
- **At-risk nodes** highlighted in red when excluding a linker study would disconnect the network
- Connected-graph check with user warning

### 7. PDF Integration
- Embedded `PDFKit` viewer (`StudyDetailView → Full Text tab`)
- Attach local PDFs via file picker; path stored in SwiftData

### 8. iCloud Sync
- `ModelConfiguration` configured with `.automatic` CloudKit database for multi-device (Mac/iPad) screening
- Falls back gracefully to local-only if iCloud is unavailable

---

## Requirements

| Component | Version |
|-----------|---------|
| macOS | 15.0+ |
| Xcode | 15.0+ |
| Swift | 6.0+ |
| SwiftData | macOS 14+ (bundled with macOS 15) |

---

## Getting Started

```bash
git clone https://github.com/Xuan-Emma/NMA-streamline.git
open NMAStreamline.xcodeproj
```

1. Select the **NMAStreamline** scheme
2. Press **⌘R** to build and run
3. Create a new project, set your PICO criteria, and import citations

---

## Project Structure

```
NMAStreamline/
├── NMAStreamlineApp.swift         # App entry, ModelContainer, Commands
├── ContentView.swift              # NavigationSplitView root
├── Models/
│   ├── NMAProject.swift           # Top-level SwiftData model
│   ├── Study.swift                # Study + StudyStatus + ExclusionReason
│   ├── Citation.swift             # Citation + CitationSource
│   ├── Outcome.swift              # Outcome + OutcomeType
│   ├── ReviewerDecision.swift     # Reviewer decision + ScreeningDecision
│   └── PICOCriteriaData.swift     # Codable PICO value type
├── Import/
│   ├── RISParser.swift            # .ris file parser
│   ├── BibParser.swift            # .bib file parser
│   ├── PubMedXMLParser.swift      # PubMed XML parser (SAX)
│   ├── DeduplicationEngine.swift  # Multi-pass dedup (Swift Actor)
│   └── ImportManager.swift        # High-level import coordinator
├── Screening/
│   ├── ScreeningView.swift        # Main screening UI (keyboard + AI hints)
│   ├── ScreeningViewModel.swift   # Dual-review logic, pre-fetch, undo
│   └── ConflictResolutionView.swift # Adjudication UI
├── AI/
│   └── AIAssistant.swift          # Protocol + RuleBasedAIAssistant + CoreMLAIAssistant
├── PRISMA/
│   └── PRISMAFlowView.swift       # PRISMA 2020 flow diagram
├── Network/
│   └── NetworkGeometryView.swift  # Node-edge network preview + spring layout
└── Views/
    ├── StudyListView.swift        # Study list with filters + import toolbar
    ├── StudyDetailView.swift      # Abstract / Outcomes / Decisions / PDF tabs
    ├── MergeWorkspaceView.swift   # Side-by-side duplicate resolver
    └── ProjectSettingsViews.swift # New project sheet, PICO editor, FlowLayout
```

---

## Testing

The test suite in `NMAStreamlineTests/` covers:

- `RISParserTests` — single/multi record parsing, missing title handling
- `BibParserTests` — BibTeX entry parsing
- `DeduplicationEngineTests` — Levenshtein distance, normalised similarity, exact/fuzzy duplicate detection
- `RuleBasedAITests` — AI availability, outcome extraction, linker identification, PICO screening
- `NMANetworkTests` — network connectivity logic

Run tests in Xcode with **⌘U**.

---

## Architecture Decisions

- **SwiftData + Actors**: `DeduplicationEngine` is a Swift actor to keep dedup off the main thread
- **Protocol-based AI**: swap `RuleBasedAIAssistant` for a CoreML/MLX implementation without changing any UI code
- **`@MainActor` `ScreeningViewModel`**: ensures all UI mutations happen on the main thread
- **`FlowLayout`**: custom `Layout` implementation for tag clouds (PICO tokens, outcome tags)
- **Local-first**: all data is stored locally; iCloud is additive and never required
