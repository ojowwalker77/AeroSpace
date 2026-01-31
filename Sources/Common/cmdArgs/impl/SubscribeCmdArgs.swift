public struct SubscribeCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) {
        self.commonState = .init(rawArgs)
    }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .subscribe,
        allowInConfig: false,
        help: subscribe_help_generated,
        flags: [
            "--all": trueBoolFlag(\.all),
        ],
        posArgs: [ArgParser(\.events, parseEventTypes)],
    )

    public var all: Bool = false
    public var events: [ServerEventType] = []
}

public func parseSubscribeCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SubscribeCmdArgs> {
    parseSpecificCmdArgs(SubscribeCmdArgs(rawArgs: args), args)
        .filter("Either --all or at least one <event> must be specified") { raw in
            raw.all || !raw.events.isEmpty
        }
        .filter("--all conflicts with specifying individual events") { raw in
            raw.all.implies(raw.events.isEmpty)
        }
        .map { raw in
            raw.all ? raw.copy(\.events, ServerEventType.allCases).copy(\.all, false) : raw
        }
}

private func parseEventTypes(_ input: ArgParserInput) -> ParsedCliArgs<[ServerEventType]> {
    var events: [ServerEventType] = []
    var advanceBy = 0
    for i in input.index ..< input.args.count {
        let arg = input.args[i]
        if arg.starts(with: "-") {
            break
        }
        guard let event = ServerEventType(rawValue: arg) else {
            let validEvents = ServerEventType.allCases.map(\.rawValue).joined(separator: ", ")
            return .fail("Unknown event '\(arg)'. Valid events: \(validEvents)", advanceBy: advanceBy + 1)
        }
        events.append(event)
        advanceBy += 1
    }
    return .succ(events, advanceBy: advanceBy)
}
