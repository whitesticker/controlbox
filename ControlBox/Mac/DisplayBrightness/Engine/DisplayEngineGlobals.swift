import Cocoa
import Foundation

let DEBUG_SW = false
let DEBUG_VIRTUAL = false
let DEBUG_MACOS10 = false
let DDC_MAX_DETECT_LIMIT: Int = 100

var app: DisplayEngine!

let prefs = UserDefaults.standard
