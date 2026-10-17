//
//  main.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

let status = await GimDiffCLI.run(arguments: CommandLine.arguments)
// Nothing the tool hands back lives in its scratch folder: `--out` writes elsewhere.
DefaultFilesystemService.removeSessionScratch()
exit(status.rawValue)
