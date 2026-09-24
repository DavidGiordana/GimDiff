//
//  main.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

exit(await GimDiffCLI.run(arguments: CommandLine.arguments).rawValue)
