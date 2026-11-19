// NSLog text is redacted to <private> for this ad-hoc-signed build; os.Logger
// with .public privacy is readable via `log show --predicate 'subsystem == "com.contxt.app"'`.

import os

private let logger = Logger(subsystem: "com.contxt.app", category: "ring")

func contxtLog(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}
