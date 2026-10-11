// The physical screens' controls for away.sh and blackout.js (bin/display.sh compiles and runs this).
//   screens                prints each real screen as "<display id><tab><name>", e.g. "2<tab>DELL U2720Q"
//   virtuals               prints each virtual display's id, one per line (other apps' test or streaming displays)
//   dim <file>             sets each external screen's brightness to 0 over DDC/CI (Apple silicon), saving
//                          the old levels to <file> first; virtual displays have no such link, so they stay on
//   undim <file>           puts the levels saved in <file> back, then removes it
//   ddc                    reads each external screen's power and brightness over DDC/CI, to see which answer
//   off <file> <ids> <pid> turns the given screens off as macOS does for an unplugged one (no signal, so each
//                          monitor goes to its own standby; virtual displays stay on), saving the ids to <file>
//                          first; prints "ready off <ids it turned off>", then holds until <pid> ends or a
//                          signal, and turns them back on
//   on <file>              turns the screens saved in <file> back on, then removes it (the fallback if off dies)
// Never DDC power or standby: standby (VCP 0xD6=4) once left an LG and a Philips dark, their own buttons
// dead and the LG still off after a replug. Brightness is safe: the monitor's buttons undo it.
// Each prints "ready ..." once it holds what it asked for, or "failed: why".
import AppKit
import CoreGraphics
import Foundation
import IOKit

func say(_ line: String) {
  print(line)
  fflush(stdout)
}

func fail(_ why: String) -> Never {
  say("failed: \(why)")
  exit(1)
}

func isAlive(_ pid: pid_t) -> Bool { pid <= 0 || kill(pid, 0) == 0 || errno == EPERM }

// MARK: displays

func activeDisplays() -> [CGDirectDisplayID] {
  var count: UInt32 = 0
  CGGetActiveDisplayList(0, nil, &count)
  var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
  CGGetActiveDisplayList(count, &ids, &count)
  return Array(ids.prefix(Int(count)))
}

/** Vendor and serial of every real screen, as the graphics hardware (IOKit) sees them. */
func hardwareScreens() -> [(vendor: UInt32, serial: UInt32?)] {
  var screens: [(vendor: UInt32, serial: UInt32?)] = []
  func each(_ serviceClass: String, _ body: (io_service_t) -> Void) {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { return }
    while case let service = IOIteratorNext(iterator), service != 0 {
      body(service)
      IOObjectRelease(service)
    }
    IOObjectRelease(iterator)
  }
  func property(_ service: io_service_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
  }
  each("IOMobileFramebuffer") { service in // Apple silicon
    guard let attributes = property(service, "DisplayAttributes") as? [String: Any],
          let product = attributes["ProductAttributes"] as? [String: Any],
          let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value else { return }
    screens.append((vendor, (product["SerialNumber"] as? NSNumber)?.uint32Value))
  }
  each("IODisplayConnect") { service in // Intel
    guard let vendor = (property(service, "DisplayVendorID") as? NSNumber)?.uint32Value else { return }
    screens.append((vendor, (property(service, "DisplaySerialNumber") as? NSNumber)?.uint32Value))
  }
  return screens
}

func isPhysical(_ id: CGDirectDisplayID, _ screens: [(vendor: UInt32, serial: UInt32?)]) -> Bool {
  CGDisplayIsBuiltin(id) != 0 || screens.contains { screen in
    screen.vendor == CGDisplayVendorNumber(id) && (screen.serial == nil || screen.serial == CGDisplaySerialNumber(id))
  }
}

/** The real screens by the names System Settings shows ("Built-in Retina Display", "DELL U2720Q"). */
func screenNames() -> [CGDirectDisplayID: String] {
  Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
    return (number.uint32Value, screen.localizedName)
  }, uniquingKeysWith: { first, _ in first })
}

func listScreens() {
  let screens = hardwareScreens()
  let names = screenNames()
  for id in activeDisplays() where isPhysical(id, screens) && CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay {
    say("\(id)\t\(names[id] ?? "Display \(id)")")
  }
}

func listVirtuals() {
  let screens = hardwareScreens()
  for id in activeDisplays() where !isPhysical(id, screens) { say("\(id)") }
}

// MARK: DDC/CI: the external screens' own controls, over the video cable

let ddcChip: UInt32 = 0x37, ddcHost: UInt32 = 0x51
let powerMode: UInt8 = 0xD6 // VCP code, read only (see the top: never written)
let brightness: UInt8 = 0x10

/** The I2C links of the external screens; the built-in screen and virtual displays have none. */
func externalLinks() -> [IOAVService] {
  var links: [IOAVService] = []
  var iterator: io_iterator_t = 0
  guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return [] }
  while case let service = IOIteratorNext(iterator), service != 0 {
    let location = IORegistryEntryCreateCFProperty(service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    if location == "External", let link = IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
      links.append(link.takeRetainedValue())
    }
    IOObjectRelease(service)
  }
  IOObjectRelease(iterator)
  return links
}

/** A DDC packet: its bytes, then their checksum (which counts the host's addresses too). */
func ddcPacket(_ bytes: [UInt8]) -> [UInt8] {
  bytes + [bytes.reduce(UInt8(0x6E ^ 0x51), ^)]
}

func ddcWrite(_ link: IOAVService, _ code: UInt8, _ value: UInt16) -> Bool {
  var packet = ddcPacket([0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
  for _ in 0..<3 {
    if IOAVServiceWriteI2C(link, ddcChip, ddcHost, &packet, UInt32(packet.count)) == kIOReturnSuccess { return true }
    usleep(20_000)
  }
  return false
}

func ddcRead(_ link: IOAVService, _ code: UInt8) -> (current: UInt16, max: UInt16)? {
  var request = ddcPacket([0x82, 0x01, code])
  var reply = [UInt8](repeating: 0, count: 12)
  for _ in 0..<3 {
    usleep(20_000)
    guard IOAVServiceWriteI2C(link, ddcChip, ddcHost, &request, UInt32(request.count)) == kIOReturnSuccess else { continue }
    usleep(50_000)
    guard IOAVServiceReadI2C(link, ddcChip, ddcHost, &reply, UInt32(reply.count)) == kIOReturnSuccess,
          reply[2] == 0x02, reply[3] == 0, reply[4] == code else { continue }
    return (UInt16(reply[8]) << 8 | UInt16(reply[9]), UInt16(reply[6]) << 8 | UInt16(reply[7]))
  }
  return nil
}

/** Saves "<screen index> <level>" per external screen that answers, then sets each to 0. */
func dim(_ file: String) {
  let levels = externalLinks().enumerated().compactMap { index, link in
    ddcRead(link, brightness).map { (index, link, $0.current) }
  }
  let saved = levels.map { "\($0.0) \($0.2)\n" }.joined()
  guard (try? saved.write(toFile: file, atomically: true, encoding: .utf8)) != nil else { fail("cannot write \(file)") }
  let done = levels.filter { ddcWrite($0.1, brightness, 0) }.count
  say("ready dimmed \(done) screen(s)")
}

func undim(_ file: String) {
  guard let saved = try? String(contentsOfFile: file, encoding: .utf8) else { return say("ready nothing to undim") }
  let links = externalLinks()
  var done = 0
  for line in saved.split(separator: "\n") {
    let parts = line.split(separator: " ").compactMap { Int($0) }
    if parts.count == 2, parts[0] < links.count, ddcWrite(links[parts[0]], brightness, UInt16(parts[1])) { done += 1 }
  }
  try? FileManager.default.removeItem(atPath: file)
  say("ready undimmed \(done) screen(s)")
}

func listDdc() {
  let describe = { (value: (current: UInt16, max: UInt16)?) in value.map { "\($0.current)/\($0.max)" } ?? "no answer" }
  for (index, link) in externalLinks().enumerated() {
    say("external \(index + 1): power \(describe(ddcRead(link, powerMode))), brightness \(describe(ddcRead(link, brightness)))")
  }
}


// MARK: screens off: disabled, as if unplugged; macOS keeps it after we exit, so every way out turns them on

typealias SetDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let setDisplayEnabled = dlsym(dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
                              "SLSConfigureDisplayEnabled").map { unsafeBitCast($0, to: SetDisplayEnabled.self) }

/** Turns each display on or off, one by one (macOS may refuse one, e.g. the last); returns those it took. */
func setEnabled(_ ids: [CGDirectDisplayID], _ enabled: Bool) -> [CGDirectDisplayID] {
  guard let setDisplayEnabled else { return [] }
  return ids.filter { id in
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return false }
    guard setDisplayEnabled(config, id, enabled) == .success else { CGCancelDisplayConfiguration(config); return false }
    return CGCompleteDisplayConfiguration(config, .forSession) == .success
  }
}

func screensOff(_ file: String, _ ids: [CGDirectDisplayID], parent: pid_t) -> Never {
  guard parent > 0 else { fail("off needs the pid it holds for") }
  guard (try? ids.map { "\($0)\n" }.joined().write(toFile: file, atomically: true, encoding: .utf8)) != nil else { fail("cannot write \(file)") }
  let done = setEnabled(ids, false)
  say("ready off \(done.map(String.init).joined(separator: ","))")
  for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { screensOn(file) }
    source.resume()
    signalSources.append(source)
  }
  while isAlive(parent) { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
  screensOn(file)
}

func screensOn(_ file: String) -> Never {
  guard let saved = try? String(contentsOfFile: file, encoding: .utf8) else { say("ready nothing to turn on"); exit(0) }
  let ids = saved.split(separator: "\n").compactMap { CGDirectDisplayID($0) }
  let done = setEnabled(ids, true)
  try? FileManager.default.removeItem(atPath: file)
  say("ready on \(done.count) screen(s)")
  exit(0)
}

var signalSources: [DispatchSourceSignal] = []
let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "screens": listScreens()
case "virtuals": listVirtuals()
case "dim": dim(arguments.dropFirst().first ?? "")
case "undim": undim(arguments.dropFirst().first ?? "")
case "ddc": listDdc()
case "off":
  let rest = Array(arguments.dropFirst())
  guard rest.count == 3 else { fail("usage: display_helper off <file> <ids> <pid>") }
  screensOff(rest[0], rest[1].split(separator: ",").compactMap { CGDirectDisplayID($0) }, parent: pid_t(rest[2]) ?? 0)
case "on": screensOn(arguments.dropFirst().first ?? "")
default: fail("usage: display_helper screens|virtuals|dim|undim|ddc|off|on ...")
}
