import AppKit

if CommandLine.arguments.contains("--selftest") {
    let report = RDPMacClient.selfTestReport()
    print(report, terminator: report.hasSuffix("\n") ? "" : "\n")
    exit(report.contains("RESULT: OK") ? 0 : 1)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
