/// A view-only flowchart of an automation, as drawn by Claude from its `SKILL.md`.
public struct ShellXAutomationFlow: Codable, Sendable, Equatable {
    /// Kind of a node.
    public enum NodeType: String, Codable, Sendable {
        /// A plain step.
        case step
        /// An automatic decision.
        case decision
        /// A point where the run waits for the user.
        case askUser
        /// An end of the flow.
        case end
    }

    /// A node of the flowchart.
    public struct Node: Codable, Sendable, Equatable {
        /// Unique id within the flow.
        public var id: String
        /// Kind of node.
        public var type: NodeType
        /// Short label.
        public var label: String
        /// Optional longer detail.
        public var detail: String?

        /// Creates a node.
        public init(id: String, type: NodeType, label: String, detail: String? = nil) {
            self.id = id
            self.type = type
            self.label = label
            self.detail = detail
        }
    }

    /// A directed edge between two nodes.
    public struct Edge: Codable, Sendable, Equatable {
        /// Id of the source node.
        public var from: String
        /// Id of the target node.
        public var to: String
        /// Optional label, such as a decision outcome.
        public var label: String?

        /// Creates an edge.
        public init(from: String, to: String, label: String? = nil) {
            self.from = from
            self.to = to
            self.label = label
        }
    }

    /// What starts the automation, in words.
    public var trigger: String?
    /// Nodes of the flow.
    public var nodes: [Node]
    /// Edges between nodes.
    public var edges: [Edge]

    /// Creates a flow.
    public init(trigger: String? = nil, nodes: [Node], edges: [Edge]) {
        self.trigger = trigger
        self.nodes = nodes
        self.edges = edges
    }

    /// True when there is at least one node, ids are unique and non-empty, and every edge joins two nodes.
    public var isUsable: Bool {
        guard !nodes.isEmpty else { return false }
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count, !ids.contains("") else { return false }
        return edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) }
    }
}
