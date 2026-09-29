//
// We need this to deal with the status bar menu
//

import AppKit
import SwiftUI

class StatusBarController {
  
  private var statusBar: NSStatusBar
  private var statusItem: NSStatusItem
  private var popover: NSPopover
  private var eventMonitor: EventMonitor?
  
  init(_ popover: NSPopover) {
    
    self.popover = popover
    statusBar = NSStatusBar.system
    statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
    
    if let statusBarButton = statusItem.button {
      // Template symbol so the icon follows the menu bar's light/dark tint like other status items
      let symbol = NSImage(systemSymbolName: "r.square", accessibilityDescription: "RSwitch")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
      if let symbol = symbol {
        symbol.isTemplate = true
        statusBarButton.image = symbol
      } else {
        statusBarButton.image = #imageLiteral(resourceName: "StatusBarIcon")
        statusBarButton.image?.size = NSSize(width: 18.0, height: 18.0)
      }
      
      statusBarButton.action = #selector(togglePopover(sender:))
      statusBarButton.target = self
    }
    
    eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)
  }
  
  @objc func togglePopover(sender: AnyObject) {
    if(popover.isShown) {
      hidePopover(sender)
    }
    else {
      showPopover(sender)
    }
  }
  
  func showPopover(_ sender: AnyObject) {
    if let statusBarButton = statusItem.button {
      popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: NSRectEdge.maxY)
      eventMonitor?.start()
    }
  }
  
  func hidePopover(_ sender: AnyObject) {
    popover.performClose(sender)
    eventMonitor?.stop()
  }
  
  func mouseEventHandler(_ event: NSEvent?) {
    if(popover.isShown) {
      hidePopover(event!)
    }
  }
  
}
