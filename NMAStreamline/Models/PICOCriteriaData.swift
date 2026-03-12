import Foundation
import SwiftData

/// PICO criteria stored alongside a project for AI-assisted screening.
/// This is a value-type wrapper stored as JSON in NMAProject.
struct PICOCriteriaData: Codable {
    var population: String
    var intervention: [String]    // treatments in the network
    var comparator: [String]      // may overlap with intervention
    var outcomes: [String]        // outcomes of interest
    var studyDesign: [String]     // e.g., ["RCT", "Crossover"]
    var additionalCriteria: String

    init(
        population: String = "",
        intervention: [String] = [],
        comparator: [String] = [],
        outcomes: [String] = [],
        studyDesign: [String] = ["RCT"],
        additionalCriteria: String = ""
    ) {
        self.population = population
        self.intervention = intervention
        self.comparator = comparator
        self.outcomes = outcomes
        self.studyDesign = studyDesign
        self.additionalCriteria = additionalCriteria
    }

    /// Human-readable summary for the AI prompt
    var promptDescription: String {
        var lines: [String] = []
        if !population.isEmpty { lines.append("Population: \(population)") }
        if !intervention.isEmpty { lines.append("Intervention(s): \(intervention.joined(separator: ", "))") }
        if !comparator.isEmpty { lines.append("Comparator(s): \(comparator.joined(separator: ", "))") }
        if !outcomes.isEmpty { lines.append("Outcomes: \(outcomes.joined(separator: ", "))") }
        if !studyDesign.isEmpty { lines.append("Study design: \(studyDesign.joined(separator: " or "))") }
        if !additionalCriteria.isEmpty { lines.append("Additional criteria: \(additionalCriteria)") }
        return lines.joined(separator: "\n")
    }
}
