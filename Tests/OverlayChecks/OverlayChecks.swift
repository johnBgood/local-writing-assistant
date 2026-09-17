import AppKit
@main struct Repro {
 @MainActor static func main() {
  _ = NSApplication.shared
  let overlay = Overlay()
  let mark = Mark(range: NSRange(location: 0,length: 25), rect: CGRect(x: 300,y: 300,width: 100,height: 20),word:"She go to work yesterday.",suggestions:[],sentence:true)
  overlay.show(mark:mark)
  let before = overlay.popover.frame
  let click = CGPoint(x:before.midX,y:before.maxY-40)
  overlay.show(mark:mark,message:"Generating locally…")
  let after = overlay.popover.frame
  print("Before:",before,"Loading:",after,"click:",click)
  guard after.insetBy(dx: -12,dy: -12).contains(click) else {
   print("FAIL: loading layout moves away from the first click; hover timeout clears displayed and discards the response")
   exit(1)
  }
  overlay.show(mark:mark,replacement:"She went to work yesterday.")
  precondition(overlay.popover.frame.insetBy(dx: -12,dy: -12).contains(click))
  overlay.hide()
  overlay.show(mark:mark,message:"Generating locally…")
  precondition(overlay.popover.frame.height < before.height, "A fresh card must not inherit old height")
  overlay.hide()
  print("PASS: first-click position survives loading and completion; fresh cards reset their size")
 }
}
