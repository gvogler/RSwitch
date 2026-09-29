//
// All this to just be able to grab metadata about the installed R versions
//

import Foundation
import Cocoa

struct RVersion: CustomStringConvertible, Hashable, Identifiable {
  
  var id = UUID()
  
  let path: String
  let major: String
  let minor: String
  let year: String
  let month: String
  let day: String
  let nick: String
  let rev: String
  let arch: String
  let isCurrent: Bool
  let isComplete: Bool
  
  var shortVersion : String { return("\(path)") }
  var fullVersion : String { return("\(major).\(minor)") }
  var verboseVersion : String { return("\(major).\(minor) (\(year)-\(month)-\(day) r\(rev)) — \"\(nick)\"") }
  var incompleteVersion : String { return("\(path) — \"\(nick)\"") }
  
  var debugDescription: String {
    return(isComplete ? verboseVersion : incompleteVersion)
  }
  
  var description: String {
    return(isComplete ? verboseVersion : incompleteVersion)
  }
  
}

class RVersions: ObservableObject {
  
  @Published var versions: [RVersion] = enumerateVersions()
  @Published var current: Int = currentVersionIndex() ?? -1
  
  static let defineRegex = try!NSRegularExpression(pattern: "#define [[:upper:]_]+[[:space:]]+|\"", options: NSRegularExpression.Options.useUnixLineSeparators)
  
  static let noRInstall =  RVersion(
    path: "/dev/null",
    major: "",
    minor: "",
    year: "",
    month: "",
    day: "",
    nick: "No R Install",
    rev: "",
    arch: "",
    isCurrent: false,
    isComplete: false
  )
  
  static let macosRFramework = "/Library/Frameworks/R.framework/Versions" // Where the official R installs go
  static let archSuffix = "-arm64" // Apple Silicon R installs live in e.g. `4.4-arm64`
  
  func updateVersions() {
    versions = RVersions.enumerateVersions()
    current = RVersions.currentVersionIndex() ?? -1
  }
  
  static func extract(from: [String.SubSequence], what: String) -> String {
    
    let res: String = from
      .filter { $0.contains(what) }
      .map {
        defineRegex.stringByReplacingMatches(
          in: String($0),
          options: [],
          range: NSMakeRange(0, $0.count),
          withTemplate: ""
        )
      }[0]
    
    return(res)
    
  }
  
  static func parseRHeaderAndAnalyzeDirectoryContents(versionPath: String) -> RVersion {
    
    let fullPath = NSString.path(withComponents: [ RVersions.macosRFramework, versionPath, "Headers", "Rversion.h" ])
    var out: RVersion

    let currentTarget = RVersions.currentVersionTarget()
    
    if (FileManager.default.fileExists(atPath: fullPath)) {
      
      do {
        
        let header = (try NSString(contentsOfFile: fullPath, encoding: String.Encoding.utf8.rawValue)) as String
        
        let lines = header.split(separator: "\n")
        let nickStr = extract(from: lines, what: "R_NICK") // #define R_NICK "Bunny-Wunnies Freak Out"
        
        out = RVersion(
          path: versionPath,
          major: extract(from: lines, what: "R_MAJOR"), // #define R_MAJOR  "4"
          minor: extract(from: lines, what: "R_MINOR"), // #define R_MINOR  "0.3"
          year: extract(from: lines, what: "R_YEAR"), // #define R_YEAR   "2020"
          month: extract(from: lines, what: "R_MONTH"), // #define R_MONTH  "10"
          day: extract(from: lines, what: "R_DAY"), // #define R_DAY    "08"
          nick: nickStr == "" ? "Unsuffered Consequences" : nickStr,
          rev: extract(from: lines, what: "R_SVN_REVISION"), // #define R_SVN_REVISION 79317
          arch: "arm64",
          isCurrent: (currentTarget == versionPath),
          isComplete: hasRBinary(versionPath: versionPath)
        )
        
      } catch {
        out = RVersion(
          path: versionPath,
          major: "",
          minor: "",
          year: "",
          month: "",
          day: "",
          nick: "Incomplete",
          rev: "",
          arch: "",
          isCurrent: false,
          isComplete: false
        )
      }
      
    } else {
      out = RVersion(
        path: versionPath,
        major: "",
        minor: "",
        year: "",
        month: "",
        day: "",
        nick: "Incomplete",
        rev: "",
        arch: "",
        isCurrent: false,
        isComplete: false
      )
    }
    
    return(out)
    
  }
  
  // Decide by the Mach-O header of R itself rather than the folder name, since
  // installers haven't always used the `-arm64` suffix
  static func isArm64(versionPath: String) -> Bool {
    
    let arm64: UInt32 = 0x0100000c // CPU_TYPE_ARM64
    let candidates = [ [ "Resources", "lib", "libR.dylib" ], [ "Resources", "bin", "exec", "R" ] ]
    
    for candidate in candidates {
      
      let binPath = NSString.path(withComponents: [ RVersions.macosRFramework, versionPath ] + candidate)
      guard let fh = FileHandle(forReadingAtPath: binPath) else { continue }
      let d = [UInt8](fh.readData(ofLength: 4096))
      fh.closeFile()
      guard d.count >= 8 else { continue }
      
      func le32(_ o: Int) -> UInt32 {
        let b0 = UInt32(d[o]), b1 = UInt32(d[o+1]) << 8, b2 = UInt32(d[o+2]) << 16, b3 = UInt32(d[o+3]) << 24
        return(b0 | b1 | b2 | b3)
      }
      func be32(_ o: Int) -> UInt32 {
        let b0 = UInt32(d[o]) << 24, b1 = UInt32(d[o+1]) << 16, b2 = UInt32(d[o+2]) << 8, b3 = UInt32(d[o+3])
        return(b0 | b1 | b2 | b3)
      }
      
      if (le32(0) == 0xfeedfacf) { return(le32(4) == arm64) } // thin 64-bit Mach-O
      
      let magic = be32(0)
      if (magic == 0xcafebabe || magic == 0xcafebabf) { // universal binary: look for an arm64 slice
        let entrySize = (magic == 0xcafebabe) ? 20 : 32
        for i in 0..<Int(be32(4)) {
          let o = 8 + i * entrySize
          if (o + 4 <= d.count && be32(o) == arm64) { return(true) }
        }
        return(false)
      }
      
    }
    
    return(versionPath.hasSuffix(archSuffix))
    
  }
  
  static func hasRBinary(versionPath: String) -> Bool {
    let resourcesPath = NSString.path(withComponents: [ RVersions.macosRFramework, versionPath, "Resources", "bin", "R" ])
    return(FileManager.default.fileExists(atPath: resourcesPath))
  }
  
  static func currentVersionTarget() -> String {
    
    // get where Current points to
    let furl = NSURL(fileURLWithPath: (RVersions.macosRFramework as NSString).appendingPathComponent("Current"))
    
    if (furl.fileReferenceURL() != nil) {
      do {
        let fdat = try NSURL(resolvingAliasFileAt: furl as URL, options: [])
        return(fdat.lastPathComponent!)
      } catch {
        return("")
      }
    } else {
      return("")
    }
    
  }
  
  static func enumerateVersions() -> [RVersion] {
    
    var entries: [RVersion]
    
    do {
      
      entries = try FileManager.default
        .contentsOfDirectory(atPath: RVersions.macosRFramework)
        .sorted()
        .filter { !($0.hasPrefix(".")) && !($0 == "Current") && isArm64(versionPath: $0) }
        .map { vers in
          parseRHeaderAndAnalyzeDirectoryContents(versionPath: vers)
        }
        .filter {
          $0.isComplete
        }
      
    } catch {
      entries = [noRInstall]
    }
    
    return(entries)
    
  }
  
  static func currentVersionIndex() -> Int? {
    return(enumerateVersions().firstIndex { (r) -> Bool in r.isCurrent })
  }
  
}


