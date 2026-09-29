import Foundation
import ArgumentParser
import CoreServices

struct RSwitch: ParsableCommand {
  
  @Argument(help: "R version. e.g. 4.1")
  var vers: String?
  
  @Flag(name: [.customShort("s"), .long], help: "No output after performing the switch.")
  var silent: Bool = false

  func shell(command: String) -> Int32 {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["bash", "-c", command]
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
  }
  
  func handleRSwitch(vers: String) {
    
    let fm = FileManager.default
    let rmLink = (RVersions.macosRFramework as NSString).appendingPathComponent("Current")

    var isDir: ObjCBool = true

    var versComponent: String = ""

    let versComponents = vers.split(separator: ".")
    if (versComponents.count >= 2) {
      versComponent = "\(versComponents[0]).\(versComponents[1])"
    } else {
      let msg = "Bad version string."
      print(msg)
      return()
    }
    
    let newLink = (RVersions.macosRFramework as NSString).appendingPathComponent("\(versComponent)\(RVersions.archSuffix)")

    if (fm.fileExists(atPath: newLink, isDirectory: &isDir)) {
      if (!isDir.boolValue) {
        let msg = "Path exists but is not a directory."
        print(msg)
        return()
      }
    } else {
      let msg = "R \(versComponent) (arm64) is not installed."
      print(msg)
      return()
    }
    
    do {
      try fm.removeItem(atPath: rmLink)
    } catch  {
      let msg = "Could not remove `Current` symlink. Check permissions in the `R.framework` folder and make sure the RSwitch CLI utility has Full Disk Access permissions."
      print(msg)
      return()
    }
    
    do {
      try fm.createSymbolicLink(
        at: NSURL(fileURLWithPath: rmLink) as URL,
        withDestinationURL: NSURL(fileURLWithPath: newLink) as URL
      )
    } catch {
      let msg = "Could not create new `Current` symlink. Check permissions in the `R.framework` folder and make sure RSwitch has Full Disk Access permissions."
      print(msg)
      return()
    }
    
    if (!silent) {
      let _ = shell(command: "R --version")
    }
    
  }
  
  mutating func run() throws {
    
    if let vers = vers  {
      
      handleRSwitch(vers: vers)
      
    } else {
      
      let versions = RVersions.enumerateVersions()
      
      if (versions.count > 0) {
        versions.forEach { vers in
          print("- \(vers)")
        }
      } else {
        print("No R installations found.")
      }
      
    }

  }
  
}

RSwitch.main()
