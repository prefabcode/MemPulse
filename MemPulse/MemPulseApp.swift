import SwiftUI
import IOKit
import Foundation

@main
struct MemoryPressureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // No main window needed
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var popover: NSPopover?
    var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let statusButton = statusItem?.button {
            statusButton.image = createImage(withColor: .systemGreen)
            statusButton.imagePosition = .imageOnly
            statusButton.image?.isTemplate = true // Adapts to dark mode
            statusButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusButton.action = #selector(self.handleClick(sender:))
            updateMemoryPressureIndicator(level: .normal)
            startPollingMemoryPressure()
        }

        // Setup the popover
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = MemoryStatsViewController()
        
        // Set up the menu
        statusMenu = NSMenu()
        statusMenu?.addItem(NSMenuItem(title: "Quit MemPulse", action: #selector(quitApp), keyEquivalent: "q"))

    }
    
    @objc func handleClick(sender: NSStatusItem) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
           // Right-click or Control-click to show the menu
           if let menu = statusMenu {
               statusItem?.menu = menu
               statusItem?.button?.performClick(nil)
               statusItem?.menu = nil // Reset the menu to nil after the menu has been displayed
           }
       } else if event.type == .leftMouseUp {
           // Left-click to toggle the popover
           togglePopover(sender: statusItem?.button)
       }
   }


    @objc func togglePopover(sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(sender)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }


    func startPollingMemoryPressure() {
        // Polling every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }

    func checkMemoryPressure() {
        let pressureLevel = getMemoryPressureLevel()
        print("Raw Memory Pressure Level from sysctl: \(pressureLevel.rawValue)") // Detailed debug information

        switch pressureLevel {
        case .critical:
            print("Memory Pressure is Critical")
            updateMemoryPressureIndicator(level: .critical)
        case .warning:
            print("Memory Pressure is Warning")
            updateMemoryPressureIndicator(level: .warning)
        case .normal:
            print("Memory Pressure is Normal")
            updateMemoryPressureIndicator(level: .normal)
        default:
            print("Memory Pressure is Unknown")
            updateMemoryPressureIndicator(level: .normal)
        }
    }

    func getMemoryPressureLevel() -> DispatchSource.MemoryPressureEvent {
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0)

        print("sysctl result: \(result), pressureLevel: \(pressureLevel)") // Additional debug info

        if result == 0 {
            switch pressureLevel {
            case 1:
                return .normal  // Green
            case 2:
                return .warning // Yellow
            case 4:
                return .critical // Red
            default:
                return .normal // Default to normal if an unexpected value is returned
            }
        } else {
            print("Error retrieving memory pressure level with sysctl.") // Error handling
            return .normal // Fallback to normal if unable to retrieve memory pressure
        }
    }

    func updateMemoryPressureIndicator(level: DispatchSource.MemoryPressureEvent) {
        guard let statusButton = statusItem?.button else { return }

        switch level {
        case .normal:
            statusButton.image = createImage(withColor: .systemGreen)
        case .warning:
            statusButton.image = createImage(withColor: .systemYellow)
        case .critical:
            statusButton.image = createImage(withColor: .systemRed)
        default:
            statusButton.image = createImage(withColor: .systemGray)
        }

        print("Updated Memory Pressure Indicator to: \(level)") // Debug information
    }
    
    func createImage(withColor color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        guard let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Memory Pressure Indicator")?.withSymbolConfiguration(config) else {
            return nil
        }

        // Create a new image with adjusted position
        let newSize = NSSize(width: 16, height: 16)
        let newImage = NSImage(size: newSize)

        newImage.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        image.draw(in: rect)
        newImage.unlockFocus()

        return newImage
    }
}

class MemoryStatsViewController: NSViewController {
    private var stackView: NSStackView?
    
    override func loadView() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .left // Align text to the left
        stackView.spacing = 10 // Space between labels
        stackView.widthAnchor.constraint(equalToConstant: 200).isActive = true
        stackView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        

        // Set padding for the stack view
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 10, bottom: 0, right: 0)

        self.stackView = stackView
        self.view = stackView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateMemoryStats()
    }

    func updateMemoryStats() {
        guard let stackView = stackView else { return }

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() } // Clear existing views

        let memoryStats = getMemoryStats()
        let labels = memoryStats.map { stat -> NSTextField in
            let label = NSTextField(labelWithString: stat)
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            
            
            // Bold the label text
            let attributedString = NSMutableAttributedString(string: stat)
            let boldFont = NSFont.boldSystemFont(ofSize: label.font?.pointSize ?? 12)
            attributedString.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: stat.firstIndex(of: ":")!.utf16Offset(in: stat)))
            label.attributedStringValue = attributedString
            
            return label
        }

        labels.forEach { stackView.addArrangedSubview($0) }
    }

    func getMemoryStats() -> [String] {
        var totalMemory: Int64 = 0
        var length = MemoryLayout.size(ofValue: totalMemory)
        sysctlbyname("hw.memsize", &totalMemory, &length, nil, 0)

        let memoryUsed = getMemoryUsage()
        let swapUsed = getSwapUsage()

        return [
            String(format: "Memory Used: %.2f GB", memoryUsed),
            String(format: "Swap Used: %.2f GB", swapUsed)
        ]
    }

    func getMemoryUsage() -> Double {
        let f1 = 0.00000000093132257 // 1/(1024*1024*1024) Converts bytes to GB

        // Get the page size
        var pagesize: Int = 0
        var size = MemoryLayout.size(ofValue: pagesize)
        sysctlbyname("hw.pagesize", &pagesize, &size, nil, 0)

        // Get memory info from vm_stat
        var vmStats = [String: Int]()
        if let vmStatOutput = runCommand(cmd: "/usr/bin/vm_stat") {
            let vmLines = vmStatOutput.split(separator: "\n")
            for row in 1..<vmLines.count-2 {
                let rowElements = vmLines[row].trimmingCharacters(in: .whitespaces).split(separator: ":")
                if rowElements.count == 2 {
                    let key = String(rowElements[0])
                    let value = Int(rowElements[1].trimmingCharacters(in: CharacterSet(charactersIn: ". ")))! * pagesize
                    vmStats[key] = value
                }
            }
        }
        
        // Calculate App Memory
        let appMemory = Double(vmStats["Anonymous pages"]! - vmStats["Pages purgeable"]!)

        // Calculate Memory Used (App Memory + Wired Memory + Compressed Memory)
        let wiredMemory = Double(vmStats["Pages wired down"]!)
        let compressedMemory = Double(vmStats["Pages occupied by compressor"]!)
        let memoryUsed = (appMemory + wiredMemory + compressedMemory) * f1

        return memoryUsed
    }

    func runCommand(cmd: String, args: [String] = []) -> String? {
        let task = Process()
        task.launchPath = cmd
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        return output
    }

    func getSwapUsage() -> Double {
        var xswUsage = xsw_usage()
        var size = MemoryLayout.size(ofValue: xswUsage)
        let result = sysctlbyname("vm.swapusage", &xswUsage, &size, nil, 0)
        if result == 0 {
            let swapUsedGB = Double(xswUsage.xsu_used) / 1024 / 1024 / 1024
            return swapUsedGB
        }
        return 0.0
    }
}

