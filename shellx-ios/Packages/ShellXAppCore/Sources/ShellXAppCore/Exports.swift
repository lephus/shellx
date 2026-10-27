// The Link wire types (`PendingItem`, `PendingQuestion`, `LinkDecision`, `ExitPlanMode`,
// `ReplyOutcome`, `AgentSession`, `ChatEntry`…) are part of ShellXAppCore's public API: its models
// and calls take and return them. Re-exporting them keeps the app target to one dependency,
// ShellXAppCore (plan decision D2): the app never imports shellx-link itself.
@_exported import ShellXLinkCore
