extension ShellXLink {
    /// Columns a phone may ask for; the host clamps into this range (PROTOCOL.md 11.3).
    public static let terminalColumns: ClosedRange<Int> = 20...300
    /// Rows a phone may ask for; the host clamps into this range (PROTOCOL.md 11.3).
    public static let terminalRows: ClosedRange<Int> = 5...120
    /// Largest `cols` or `rows` in a frame (PROTOCOL.md 11.5).
    public static let terminalMaxGridSize = 1000
    /// Most parts of one frame.
    public static let terminalMaxFrameParts = 256
    /// Most UTF-8 bytes in the text of one cell.
    public static let terminalMaxCellTextBytes = 32
    /// History rows a snapshot carries at most.
    public static let terminalSnapshotHistoryRows = 240
    /// History rows of a snapshot and its history frames together.
    public static let terminalHistoryRowBudget = 4000
    /// Bytes of the messages of the history frames that follow one snapshot.
    public static let terminalHistoryFillMaxBytes = 262_144
    /// History rows a delta carries at most.
    public static let terminalMaxDeltaHistoryRows = 2000
    /// Units in one `terminal.view.input`.
    public static let terminalMaxInputUnits = 64
    /// UTF-8 bytes of typed text in one `terminal.view.input`.
    public static let terminalMaxTextBytes = 4096
    /// UTF-8 bytes of pasted text in one `terminal.view.input`.
    public static let terminalMaxPasteBytes = 16_384
    /// Most lines of a `scroll` unit, either sign.
    public static let terminalMaxScrollLines = 100
    /// Input and resize messages of a view a host holds unapplied.
    public static let terminalMaxQueuedInputs = 64
}
