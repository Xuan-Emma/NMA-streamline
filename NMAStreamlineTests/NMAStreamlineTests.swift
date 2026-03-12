import XCTest
@testable import NMAStreamline

// NOTE: These tests exercise the platform-agnostic logic in the parsers
// and the deduplication engine. They can be run on any Swift platform.

// MARK: - RIS Parser Tests

final class RISParserTests: XCTestCase {

    func testParsesSingleRISRecord() {
        let ris = """
        TY  - JOUR
        TI  - Efficacy of Drug A vs Drug B in MDD
        AU  - Smith, John
        AU  - Doe, Jane
        PY  - 2022
        JO  - Journal of Clinical Psychiatry
        DO  - 10.1234/jcp.2022.001
        AB  - Background: This study compared Drug A and Drug B.
        ER  -
        """
        let citations = RISParser.parse(ris)
        XCTAssertEqual(citations.count, 1)
        let c = citations[0]
        XCTAssertEqual(c.title, "Efficacy of Drug A vs Drug B in MDD")
        XCTAssertEqual(c.authors.count, 2)
        XCTAssertEqual(c.year, 2022)
        XCTAssertEqual(c.doi, "10.1234/jcp.2022.001")
        XCTAssertTrue(c.abstract.contains("Drug A"))
    }

    func testParsesMultipleRISRecords() {
        let ris = """
        TY  - JOUR
        TI  - Study One
        AU  - Author, A
        PY  - 2020
        ER  -
        TY  - JOUR
        TI  - Study Two
        AU  - Author, B
        PY  - 2021
        ER  -
        """
        let citations = RISParser.parse(ris)
        XCTAssertEqual(citations.count, 2)
        XCTAssertEqual(citations[0].title, "Study One")
        XCTAssertEqual(citations[1].title, "Study Two")
    }

    func testEmptyRISReturnsNoCitations() {
        let citations = RISParser.parse("")
        XCTAssertTrue(citations.isEmpty)
    }

    func testRISWithMissingTitleIsSkipped() {
        let ris = """
        TY  - JOUR
        AU  - Smith, John
        PY  - 2022
        ER  -
        """
        let citations = RISParser.parse(ris)
        XCTAssertTrue(citations.isEmpty)
    }
}

// MARK: - BibTeX Parser Tests

final class BibParserTests: XCTestCase {

    func testParsesSingleBibEntry() {
        let bib = """
        @article{smith2022,
          title = {A Randomized Trial of Drug A},
          author = {Smith, John and Jones, Emily},
          year = {2022},
          journal = {Lancet},
          doi = {10.1016/lancet.2022.001},
          abstract = {This is the abstract.}
        }
        """
        let citations = BibParser.parse(bib)
        XCTAssertEqual(citations.count, 1)
        let c = citations[0]
        XCTAssertEqual(c.title, "A Randomized Trial of Drug A")
        XCTAssertEqual(c.authors.count, 2)
        XCTAssertEqual(c.year, 2022)
        XCTAssertEqual(c.doi, "10.1016/lancet.2022.001")
    }

    func testParsesMultipleBibEntries() {
        let bib = """
        @article{a2020, title = {First Study}, year = {2020}}
        @article{b2021, title = {Second Study}, year = {2021}}
        """
        let citations = BibParser.parse(bib)
        XCTAssertEqual(citations.count, 2)
    }

    func testBibWithNoTitleIsSkipped() {
        let bib = "@article{noTitle, author = {A, B}, year = {2020}}"
        let citations = BibParser.parse(bib)
        XCTAssertTrue(citations.isEmpty)
    }
}

// MARK: - Deduplication Engine Tests

final class DeduplicationEngineTests: XCTestCase {

    let engine = DeduplicationEngine()

    // MARK: Levenshtein distance

    func testLevenshteinIdenticalStrings() {
        let dist = engine.levenshteinDistance("hello", "hello")
        XCTAssertEqual(dist, 0)
    }

    func testLevenshteinOneInsertion() {
        // "cat" -> "cats"
        let dist = engine.levenshteinDistance("cat", "cats")
        XCTAssertEqual(dist, 1)
    }

    func testLevenshteinOneDeletion() {
        let dist = engine.levenshteinDistance("cats", "cat")
        XCTAssertEqual(dist, 1)
    }

    func testLevenshteinOneSubstitution() {
        let dist = engine.levenshteinDistance("cat", "car")
        XCTAssertEqual(dist, 1)
    }

    func testLevenshteinCompletelyDifferent() {
        let dist = engine.levenshteinDistance("abc", "xyz")
        XCTAssertEqual(dist, 3)
    }

    func testLevenshteinEmptyStrings() {
        XCTAssertEqual(engine.levenshteinDistance("", ""), 0)
        XCTAssertEqual(engine.levenshteinDistance("abc", ""), 3)
        XCTAssertEqual(engine.levenshteinDistance("", "abc"), 3)
    }

    // MARK: Normalised Levenshtein

    func testNormalisedLevenshteinIdentical() {
        let sim = engine.normalizedLevenshtein("hello", "hello")
        XCTAssertEqual(sim, 1.0, accuracy: 0.001)
    }

    func testNormalisedLevenshteinEmpty() {
        let sim = engine.normalizedLevenshtein("", "abc")
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testNormalisedLevenshteinSimilar() {
        // "kitten" vs "sitting": distance 3, max 7 → similarity ≈ 0.571
        let sim = engine.normalizedLevenshtein("kitten", "sitting")
        XCTAssertGreaterThan(sim, 0.5)
        XCTAssertLessThan(sim, 0.7)
    }

    // MARK: Exact duplicate detection (async)

    func testExactDOIDuplicateDetected() async {
        let c1 = Citation(title: "Study A", doi: "10.1234/abc")
        let c2 = Citation(title: "Study A (duplicate)", doi: "10.1234/abc")
        let matches = await engine.findDuplicates(in: [c1, c2])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.matchType, .exactDOI)
        XCTAssertEqual(matches.first?.similarity, 1.0)
    }

    func testExactPMIDDuplicateDetected() async {
        let c1 = Citation(title: "Study B", pmid: "12345678")
        let c2 = Citation(title: "Study B repub", pmid: "12345678")
        let matches = await engine.findDuplicates(in: [c1, c2])
        let pmidMatches = matches.filter { $0.matchType == .exactPMID }
        XCTAssertFalse(pmidMatches.isEmpty)
    }

    func testNoDuplicatesWithDifferentIdentifiers() async {
        let c1 = Citation(title: "Study C", doi: "10.1234/aaa")
        let c2 = Citation(title: "Study D", doi: "10.1234/bbb")
        let matches = await engine.findDuplicates(in: [c1, c2])
        XCTAssertTrue(matches.isEmpty)
    }

    func testFuzzyDuplicateDetected() async {
        // Very similar titles, same year, same first author
        let c1 = Citation(
            title: "Efficacy of Drug A versus Drug B in Major Depression: A Randomised Trial",
            authors: ["Smith, John"],
            year: 2021
        )
        let c2 = Citation(
            title: "Efficacy of Drug A versus Drug B in Major Depression: A Randomized Trial",
            authors: ["Smith, John"],
            year: 2021
        )
        let matches = await engine.findDuplicates(in: [c1, c2])
        XCTAssertFalse(matches.isEmpty, "Highly similar titles should be detected as duplicates")
        if let m = matches.first {
            XCTAssertGreaterThan(m.similarity, 0.85)
        }
    }

    func testFuzzyNonDuplicateNotFlagged() async {
        let c1 = Citation(
            title: "Cognitive Behavioural Therapy for Depression",
            authors: ["Jones, Alice"],
            year: 2018
        )
        let c2 = Citation(
            title: "Pharmacotherapy for Anxiety Disorders",
            authors: ["Brown, Bob"],
            year: 2020
        )
        let matches = await engine.findDuplicates(in: [c1, c2])
        XCTAssertTrue(matches.isEmpty)
    }
}

// MARK: - AI Rule-based assistant tests

final class RuleBasedAITests: XCTestCase {

    let ai = RuleBasedAIAssistant()

    func testAlwaysAvailable() async {
        let available = await ai.isAvailable()
        XCTAssertTrue(available)
    }

    func testExtractsOutcomesFromAbstract() async {
        let abstract = "The primary endpoint was overall survival. Secondary endpoints included progression-free survival and quality of life."
        let outcomes = await ai.extractOutcomes(from: abstract)
        XCTAssertTrue(outcomes.contains("overall survival"))
        XCTAssertTrue(outcomes.contains("progression"))
    }

    func testIdentifiesLinkerOutcomes() async {
        let outcomes = ["overall survival", "quality of life", "blood pressure"]
        let linkers = await ai.identifyLinkerOutcomes(
            outcomes: outcomes,
            networkInterventions: ["Drug A", "Drug B"]
        )
        XCTAssertTrue(linkers.contains("overall survival"))
    }

    func testSuggestExcludeForNonRCT() async {
        let citation = Citation(
            title: "Observational Study of Drug A",
            abstract: "A retrospective cohort study examining outcomes. No randomization was performed.",
            authors: ["Author A"]
        )
        let pico = PICOCriteriaData(studyDesign: ["RCT", "Randomized"])
        let suggestion = await ai.suggest(for: citation, pico: pico)
        XCTAssertNotNil(suggestion)
        // Should flag no RCT design
        XCTAssertFalse(suggestion!.picoFlags.isEmpty)
    }

    func testSuggestIncludeForMatchingCriteria() async {
        let citation = Citation(
            title: "A Randomized Controlled Trial of Drug A vs Placebo in Patients with Major Depression",
            abstract: "Background: We conducted a double-blind randomized controlled trial of drug a versus placebo in adult patients with major depressive disorder. Primary outcome was overall survival at 12 months.",
            authors: ["Smith, J"]
        )
        let pico = PICOCriteriaData(
            population: "major depressive disorder",
            intervention: ["drug a"],
            comparator: ["placebo"],
            outcomes: ["overall survival"],
            studyDesign: ["randomized", "rct"]
        )
        let suggestion = await ai.suggest(for: citation, pico: pico)
        XCTAssertNotNil(suggestion)
        // Should lean toward include with high confidence
        XCTAssertEqual(suggestion!.recommendation, .include)
    }
}

// MARK: - Network geometry tests

final class NMANetworkTests: XCTestCase {

    func testEmptyProjectHasNoNodes() {
        let project = NMAProject(title: "Test")
        let network = NMANetwork(project: project)
        XCTAssertTrue(network.nodes.isEmpty)
        XCTAssertTrue(network.edges.isEmpty)
    }

    func testConnectedSubgraph() {
        // Manual edge test
        let nodes = ["A", "B", "C"]
        let edges = [
            NetworkEdge(from: "A", to: "B", studyCount: 1, isIndirect: false),
            NetworkEdge(from: "B", to: "C", studyCount: 1, isIndirect: false),
        ]
        // Manually verify connectivity logic
        var visited = Set<String>()
        var queue = [nodes[0]]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            let neighbors = edges
                .filter { $0.from == current || $0.to == current }
                .map { $0.from == current ? $0.to : $0.from }
                .filter { nodes.contains($0) }
            queue.append(contentsOf: neighbors)
        }
        XCTAssertEqual(visited.count, nodes.count)
    }
}
