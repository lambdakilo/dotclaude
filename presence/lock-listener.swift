// Keeps the marker file that CLAUDE_CLIENT_PRESENCE_FILE names in step with the
// screen lock: the file exists while the screen is unlocked and is gone while it
// is locked. Claude Code skips its Remote Control pushes to the phone while the
// file exists, so they arrive only while the Mac is locked. The LaunchAgent that
// install.sh writes runs it with the file's path as its one argument.

import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: lock-listener <marker file>\n".utf8))
  exit(64)
}
let marker = CommandLine.arguments[1]

func record(locked: Bool) {
  if locked {
    try? FileManager.default.removeItem(atPath: marker)
  } else {
    FileManager.default.createFile(atPath: marker, contents: nil)
  }
  print("\(Date()) \(locked ? "locked" : "unlocked")")
  fflush(stdout)
}

// The key is undocumented but the only way to read the state at start.
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
record(locked: session?["CGSSessionScreenIsLocked"] as? Bool ?? false)

let center = DistributedNotificationCenter.default()
center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil) { _ in
  record(locked: true)
}
center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: nil) { _ in
  record(locked: false)
}

// A stopped listener can no longer tell, so pushes go out as if no file were set.
signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler {
  try? FileManager.default.removeItem(atPath: marker)
  exit(0)
}
term.resume()

RunLoop.main.run()
