// Minimal CoreAudio default-device tool. Compiled and cached by `audio-route`.
//
// macOS ships no CLI for reading or setting the default input and output
// device — `SwitchAudioSource` is the usual answer, but that is a Homebrew
// install to do what is four CoreAudio properties. This is those four.
//
//   audiodev list in|out         uid<TAB>name, one device per line
//   audiodev get  in|out         uid<TAB>name of the current default
//   audiodev set  in|out <spec>  spec is a device UID, or an exact name,
//                                or a case-insensitive substring of one
//   audiodev subs <spec>         uid<TAB>name of each sub-device of an
//                                aggregate; nothing for a plain device
//   audiodev make-multi <name> <main> <extra>
//                                create a Multi-Output Device: <main> and
//                                <extra> stacked, clocked to <main>
//
// Exit 0 on success, 1 on a bad argument, 2 when a device cannot be found or
// the set is refused by CoreAudio.

import CoreAudio
import Foundation

let SYS = AudioObjectID(kAudioObjectSystemObject)

func addr(_ sel: AudioObjectPropertySelector,
          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
          -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(mSelector: sel, mScope: scope,
                             mElement: kAudioObjectPropertyElementMain)
}

func allDevices() -> [AudioDeviceID] {
  var a = addr(kAudioHardwarePropertyDevices)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(SYS, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  guard AudioObjectGetPropertyData(SYS, &a, 0, nil, &size, &ids) == noErr else { return [] }
  return ids
}

func stringProp(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
  var a = addr(sel)
  var size = UInt32(MemoryLayout<CFString?>.size)
  var cf: CFString? = nil
  let st = withUnsafeMutablePointer(to: &cf) {
    $0.withMemoryRebound(to: UInt8.self, capacity: Int(size)) {
      AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0)
    }
  }
  guard st == noErr, let s = cf else { return "" }
  return s as String
}

let name = { (id: AudioDeviceID) in stringProp(id, kAudioObjectPropertyName) }
let uid  = { (id: AudioDeviceID) in stringProp(id, kAudioDevicePropertyDeviceUID) }

// A device is an input or an output depending on which scope carries channels.
// Aggregates and multi-output devices show up here exactly like hardware does.
func channelCount(_ id: AudioDeviceID, input: Bool) -> Int {
  var a = addr(kAudioDevicePropertyStreamConfiguration,
               input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
  let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                             alignment: MemoryLayout<AudioBufferList>.alignment)
  defer { raw.deallocate() }
  guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
  let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
  return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func devices(input: Bool) -> [AudioDeviceID] {
  allDevices().filter { channelCount($0, input: input) > 0 }
}

func defaultDevice(input: Bool) -> AudioDeviceID {
  var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice
                     : kAudioHardwarePropertyDefaultOutputDevice)
  var id = AudioDeviceID(0)
  var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  AudioObjectGetPropertyData(SYS, &a, 0, nil, &size, &id)
  return id
}

func setDefault(input: Bool, _ id: AudioDeviceID) -> Bool {
  var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice
                     : kAudioHardwarePropertyDefaultOutputDevice)
  var v = id
  return AudioObjectSetPropertyData(SYS, &a, 0, nil,
                                    UInt32(MemoryLayout<AudioDeviceID>.size), &v) == noErr
}

// UID first — it survives renames and is what the snapshot stores. Then an
// exact name, then a substring, so "blackhole" finds "BlackHole 2ch".
func resolve(_ spec: String, input: Bool) -> AudioDeviceID? {
  let pool = devices(input: input)
  if let d = pool.first(where: { uid($0) == spec }) { return d }
  if let d = pool.first(where: { name($0) == spec }) { return d }
  let needle = spec.lowercased()
  return pool.first { name($0).lowercased().contains(needle) }
}

// Sub-device UIDs of an aggregate. A Multi-Output Device is a "stacked"
// aggregate, so this is how you learn which BlackHole it actually feeds.
// A plain device has no such property and yields an empty list.
func subDevices(_ id: AudioDeviceID) -> [String] {
  var a = addr(kAudioAggregateDevicePropertyFullSubDeviceList)
  var size = UInt32(MemoryLayout<CFArray?>.size)
  var cf: CFArray? = nil
  let st = withUnsafeMutablePointer(to: &cf) {
    $0.withMemoryRebound(to: UInt8.self, capacity: Int(size)) {
      AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0)
    }
  }
  guard st == noErr, let uids = cf as? [String] else { return [] }
  return uids
}

func die(_ msg: String, _ code: Int32) -> Never {
  FileHandle.standardError.write(("audiodev: " + msg + "\n").data(using: .utf8)!)
  exit(code)
}

func usage() -> Never {
  die("usage: audiodev list|get|set in|out [device] | subs <device> | make-multi <name> <main> <extra>", 1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "list", "get", "set":
  guard args.count >= 2, ["in", "out"].contains(args[1]) else { usage() }
  let isInput = args[1] == "in"
  switch cmd {
  case "list":
    for d in devices(input: isInput) { print(uid(d) + "\t" + name(d)) }
  case "get":
    let d = defaultDevice(input: isInput)
    guard d != 0 else { die("no default \(args[1])put device", 2) }
    print(uid(d) + "\t" + name(d))
  default:
    guard args.count >= 3 else { die("set needs a device", 1) }
    guard let d = resolve(args[2], input: isInput) else { die("no \(args[1])put device matching \"\(args[2])\"", 2) }
    guard setDefault(input: isInput, d) else { die("CoreAudio refused to make \"\(name(d))\" the default", 2) }
    print(uid(d) + "\t" + name(d))
  }
case "subs":
  guard args.count == 2 else { usage() }
  guard let d = resolve(args[1], input: false) else { die("no output device matching \"\(args[1])\"", 2) }
  let byUID = Dictionary(allDevices().map { (uid($0), $0) }, uniquingKeysWith: { a, _ in a })
  for u in subDevices(d) { print(u + "\t" + (byUID[u].map(name) ?? "")) }
case "make-multi":
  guard args.count == 4 else { usage() }
  guard let main  = resolve(args[2], input: false) else { die("no output device matching \"\(args[2])\"", 2) }
  guard let extra = resolve(args[3], input: false) else { die("no output device matching \"\(args[3])\"", 2) }
  // String keys mirror kAudioAggregateDevice*Key / kAudioSubDevice*Key.
  // "stacked" is what makes this a Multi-Output Device rather than a plain
  // aggregate; "drift" resamples the extra device against the main clock.
  // Public (not "private"), so it persists and shows in Audio MIDI Setup.
  let desc: [String: Any] = [
    "name": args[1],
    "uid": "loopback-multi-" + UUID().uuidString,
    "stacked": 1,
    "private": 0,
    "master": uid(main),
    "subdevices": [["uid": uid(main)], ["uid": uid(extra), "drift": 1]],
  ]
  var agg = AudioObjectID(0)
  guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg) == noErr else {
    die("CoreAudio refused to create \"\(args[1])\"", 2)
  }
  print(uid(agg) + "\t" + name(agg))
default:
  usage()
}
