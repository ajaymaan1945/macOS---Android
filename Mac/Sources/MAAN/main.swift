import AppKit
import Foundation
import Network
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

final class MAANSocket {
    private let connection: NWConnection
    private var buffer = Data()
    var onMessage: (([String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?

    init() { connection = NWConnection(host: "127.0.0.1", port: 8766, using: .tcp) }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.receive() }
            if case .failed = state { self?.onDisconnect?() }
        }
        connection.start(queue: .main)
    }
    func send(_ object: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: object), var line = String(data: d, encoding: .utf8)?.data(using: .utf8) else { return }
        line.append(10)
        connection.send(content: line, completion: .contentProcessed { _ in })
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_777_216) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data {
                buffer.append(data)
                while let range = buffer.firstRange(of: Data([10])) {
                    let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onMessage?(obj) }
                }
            }
            if complete || error != nil { onDisconnect?() } else { receive() }
        }
    }
}

final class RingPlayer {
    private var player: AVAudioPlayer?
    func start() {
        guard player == nil, let url = Bundle.main.url(forResource: "ring", withExtension: "wav") else { return }
        player = try? AVAudioPlayer(contentsOf: url); player?.numberOfLoops = -1; player?.volume = 0.7; player?.play()
    }
    func stop() { player?.stop(); player = nil }
}

final class CallPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var down: NSPoint = .zero
    override func mouseDown(with event: NSEvent) { down = event.locationInWindow; super.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { let up = event.locationInWindow; if hypot(up.x-down.x, up.y-down.y) > 80 { onDismiss?() }; super.mouseUp(with: event) }
}

final class ScreenView: NSView {
    var image: NSImage?
    var onTap: ((CGFloat, CGFloat, CGFloat, CGFloat) -> Void)?
    var onSwipe: ((CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Int) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onFileProbe: ((CGFloat, CGFloat, CGFloat, CGFloat) -> Void)?
    var onFileCommit: ((String, String) -> Void)?
    var onStartPhoneFileDrag: ((String, String, NSPoint) -> Void)?
    private var down: NSPoint = .zero
    private var downTime: TimeInterval = 0
    private var dragging = false
    private var fileCandidateURI: String?
    private var fileCandidateName: String?
    private var lastFileProbe = ProcessInfo.processInfo.systemUptime
    private var startedPhoneFileDrag = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([.fileURL]); wantsLayer = true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); dirtyRect.fill()
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func normalized(_ point: NSPoint) -> (CGFloat, CGFloat) {
        let safeW = max(bounds.width, 1); let safeH = max(bounds.height, 1)
        return (min(max(point.x / safeW, 0), 1), min(max((safeH - point.y) / safeH, 0), 1))
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        down = convert(e.locationInWindow, from: nil)
        downTime = ProcessInfo.processInfo.systemUptime
        dragging = false
        startedPhoneFileDrag = false
        fileCandidateURI = nil; fileCandidateName = nil
        let (px, py) = normalized(down)
        onFileProbe?(px, py, self.bounds.width, self.bounds.height)
    }

    override func mouseDragged(with e: NSEvent) {
        dragging = true
        let point = convert(e.locationInWindow, from: nil)
        let distance = hypot(point.x - down.x, point.y - down.y)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFileProbe > 0.06 {
            lastFileProbe = now
            let (px, py) = normalized(point)
            onFileProbe?(px, py, self.bounds.width, self.bounds.height)
        }
        if !startedPhoneFileDrag, distance > 12, let uri = fileCandidateURI, let name = fileCandidateName {
            startedPhoneFileDrag = true
            onStartPhoneFileDrag?(uri, name, down)
        }
    }

    override func mouseUp(with e: NSEvent) {
        let up = convert(e.locationInWindow, from: nil)
        let (x, y) = normalized(up); let (x1, y1) = normalized(down)
        let distance = hypot(up.x-down.x, up.y-down.y)
        if distance < 10 {
            onTap?(x, y, self.bounds.width, self.bounds.height)
        } else if !startedPhoneFileDrag, let uri = fileCandidateURI {
            onFileCommit?(uri, fileCandidateName ?? "file")
        } else if !startedPhoneFileDrag {
            let elapsed = ProcessInfo.processInfo.systemUptime - downTime
            let duration = Int(min(max(elapsed * 1000, 120), 2500))
            onSwipe?(x1, y1, x, y, self.bounds.width, self.bounds.height, duration)
        }
        fileCandidateURI = nil; fileCandidateName = nil
        dragging = false
        startedPhoneFileDrag = false
    }

    func setFileCandidate(success: Bool, uri: String?, name: String?) {
        fileCandidateURI = success ? uri : nil
        fileCandidateName = success ? name : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls); return true
    }
}

final class PhoneFilePromise: NSObject, NSFilePromiseProviderDelegate {
    let uri: String
    let fileName: String
    let request: (_ uri: String, _ name: String, _ destination: URL, _ completion: @escaping (Error?) -> Void) -> Void

    init(uri: String, fileName: String, request: @escaping (_ uri: String, _ name: String, _ destination: URL, _ completion: @escaping (Error?) -> Void) -> Void) {
        self.uri = uri; self.fileName = fileName; self.request = request
        super.init()
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { fileName }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        request(uri, fileName, url, completionHandler)
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }
}

final class MAANApp: NSObject, NSApplicationDelegate, NSDraggingSource {
    private var statusItem: NSStatusItem!
    private var socket: MAANSocket!
    private let ring = RingPlayer()
    private var panel: CallPanel?
    private var screenWindow: NSWindow?
    private var screenView: ScreenView?
    private var callID: String?
    private var clipboardChange = NSPasteboard.general.changeCount
    private var phoneFilePromise: PhoneFilePromise?
    private var pendingDownloads: [String: (destination: URL, completion: (Error?) -> Void, name: String)] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MAAN ●"
        let menu = NSMenu(); menu.addItem(NSMenuItem(title:"Open MAAN", action:#selector(openMain), keyEquivalent:"")); menu.addItem(NSMenuItem(title:"Open Phone Files", action:#selector(openPhoneFiles), keyEquivalent:"")); menu.addItem(NSMenuItem(title:"Send File to Phone…", action:#selector(chooseFileToSend), keyEquivalent:"")); menu.addItem(NSMenuItem.separator()); menu.addItem(NSMenuItem(title:"Quit", action:#selector(quit), keyEquivalent:"q")); statusItem.menu = menu
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        connect()
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.syncClipboard() }
    }

    private func connect() {
        socket = MAANSocket(); socket.onMessage = { [weak self] obj in self?.handle(obj) }; socket.onDisconnect = { [weak self] in DispatchQueue.main.asyncAfter(deadline:.now()+1){ self?.connect() } }; socket.start()
    }

    private func handle(_ o: [String: Any]) {
        guard let type = o["type"] as? String else { return }
        switch type {
        case "incoming_call": showCall(o)
        case "call_state": if let state = o["state"] as? String, ["ANSWERED","REJECTED","ENDED","MISSED"].contains(state) { hideCall() }
        case "dismiss_call": hideCall()
        case "screen_frame": showFrame(o)
        case "screen_error": if let message = o["message"] as? String { showTransferMessage("Screen sharing", message) }
        case "screen_stopped": screenWindow?.orderOut(nil)
        case "pair_request": showPairing(o)
        case "file_received":
            if let path = o["path"] as? String { showTransferMessage("File received", "Saved to:\n\(path)") }
        case "file_progress": break
        case "clipboard_text": if let text = o["text"] as? String { setClipboardText(text) }
        case "clipboard_image": if let data = o["data"] as? String { setClipboardImage(data) }
        case "file_drag_chunk": handlePhoneFileChunk(o)
        case "file_drag_end": handlePhoneFileEnd(o)
        case "file_drag_candidate":
            screenView?.setFileCandidate(success: o["success"] as? Bool ?? false, uri: o["uri"] as? String, name: o["name"] as? String)
        case "file_drag_result":
            if let message = o["message"] as? String { showTransferMessage("Phone → Mac", message) }
        case "input_ready":
            if let enabled = o["enabled"] as? Bool { showTransferMessage("MAAN Remote Control", enabled ? "Touch control is ready." : "Touch control is disabled.") }
        case "input_result":
            if let success = o["success"] as? Bool, !success, let message = o["message"] as? String { showTransferMessage("Remote control", message) }
        default: break
        }
    }

    private func showTransferMessage(_ title: String, _ message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "maan-" + UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func showPairing(_ o:[String:Any]) {
        let code = o["code"] as? String ?? "------"; let device = o["device"] as? String ?? "Android phone"
        let alert = NSAlert(); alert.messageText = "Pair MAAN with this device?"; alert.informativeText = "Device: \(device)\nPairing code: \(code)"; alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { socket.send(["type":"pair_approve", "code":code]) }
    }

    private func showCall(_ o:[String:Any]) {
        callID = o["call_id"] as? String; ring.start()
        let p = CallPanel(contentRect:NSRect(x:0,y:0,width:360,height:220), styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
        p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        let v = NSVisualEffectView(frame:p.contentView!.bounds); v.autoresizingMask = [.width,.height]; v.material = .hudWindow; v.state = .active; v.wantsLayer = true; v.layer?.cornerRadius = 24
        let name = NSTextField(labelWithString:o["name"] as? String ?? "Unknown Caller"); name.font = .systemFont(ofSize:22,weight:.semibold); name.alignment = .center; name.frame = NSRect(x:20,y:130,width:320,height:30)
        let number = NSTextField(labelWithString:o["number"] as? String ?? "Unknown Number"); number.font = .systemFont(ofSize:14); number.alignment = .center; number.frame = NSRect(x:20,y:105,width:320,height:22)
        let reject = NSButton(title:"Reject",target:self,action:#selector(rejectCall)); reject.frame = NSRect(x:35,y:35,width:125,height:42); reject.bezelStyle = .rounded; reject.contentTintColor = .systemRed
        let answer = NSButton(title:"Answer",target:self,action:#selector(answerCall)); answer.frame = NSRect(x:200,y:35,width:125,height:42); answer.bezelStyle = .rounded
        let close = NSButton(title:"×",target:self,action:#selector(dismissCall)); close.isBordered = false; close.font = .systemFont(ofSize:22); close.frame = NSRect(x:315,y:175,width:30,height:30)
        [name,number,reject,answer,close].forEach{v.addSubview($0)}; p.contentView = v; p.onDismiss = { [weak self] in self?.dismissCall() }
        if let screen = NSScreen.main { let f = screen.visibleFrame; p.setFrameOrigin(NSPoint(x:f.maxX-p.frame.width-18,y:f.maxY-p.frame.height-18)) }; p.orderFrontRegardless(); panel = p
    }

    @objc private func answerCall(){ socket.send(["type":"notifier_action","action":"answer_call","call_id":callID ?? ""]) }
    @objc private func rejectCall(){ socket.send(["type":"notifier_action","action":"reject_call","call_id":callID ?? ""]) }
    @objc private func dismissCall(){ socket.send(["type":"notifier_action","action":"dismiss_call","call_id":callID ?? ""]); hideCall() }
    private func hideCall(){ ring.stop(); panel?.orderOut(nil); panel = nil; callID = nil }

    @objc private func openMain(){
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:390),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); w.title = "MAAN"; w.center()
        let label = NSTextField(labelWithString:"MAAN\n\nConnected devices\n• Android phone\n\nCalls: ON\nClipboard: ON\nScreen sharing: Ready\nRemote control: Ready when Accessibility is ON\n\nFiles: drag a file onto the phone screen window to send it.\nPhone → Mac files are saved in ~/Downloads/MAAN."); label.frame = NSRect(x:30,y:30,width:440,height:330); label.font = .systemFont(ofSize:16); label.lineBreakMode = .byWordWrapping; w.contentView = label; w.makeKeyAndOrderFront(nil)
    }

    @objc private func openPhoneFiles() {
        socket.send(["type":"open_file_bridge"])
        if screenWindow == nil { return }
        screenWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func chooseFileToSend(){
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        sendFile(url)
    }

    private func sendFile(_ url: URL) {
        Thread { [weak self] in
            guard let self, let input = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? input.close() }
            let id = "tx-" + UUID().uuidString; var offset: Int64 = 0
            while true {
                let data = input.readData(ofLength: 48 * 1024); if data.isEmpty { break }
                self.socket.send(["type":"file_chunk","transfer_id":id,"name":url.lastPathComponent,"offset":offset,"data":data.base64EncodedString()])
                offset += Int64(data.count); Thread.sleep(forTimeInterval: 0.02)
            }
            self.socket.send(["type":"file_end","transfer_id":id,"name":url.lastPathComponent])
        }.start()
    }

    @objc private func quit(){ NSApp.terminate(nil) }

    private func showFrame(_ o:[String:Any]) {
        guard let s = o["data"] as? String, let d = Data(base64Encoded:s), let image = NSImage(data:d) else { return }
        if screenWindow == nil {
            let v = ScreenView(frame:NSRect(x:0,y:0,width:420,height:760))
            v.onTap = { [weak self] x,y,w,h in self?.socket.send(["type":"input_tap","x":x,"y":y,"screen_width":w,"screen_height":h]) }
            v.onSwipe = { [weak self] x1,y1,x2,y2,w,h,duration in self?.socket.send(["type":"input_swipe","x1":x1,"y1":y1,"x2":x2,"y2":y2,"screen_width":w,"screen_height":h,"duration":duration]) }
            v.onFileProbe = { [weak self] x,y,w,h in self?.socket.send(["type":"file_drag_probe","x":x,"y":y,"screen_width":w,"screen_height":h]) }
            v.onFileCommit = { [weak self] uri,name in self?.socket.send(["type":"file_drag_commit","uri":uri,"name":name]) }
            v.onStartPhoneFileDrag = { [weak self, weak v] uri,name,point in self?.beginPhoneFileDrag(uri: uri, name: name, from: point, view: v) }
            v.onFilesDropped = { [weak self] urls in urls.forEach { self?.sendFile($0) } }
            let w = NSWindow(contentRect:v.bounds,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); w.title = "MAAN — Phone"; w.contentView = v; w.center(); w.makeKeyAndOrderFront(nil); w.makeFirstResponder(v); screenWindow = w; screenView = v
        }
        screenView?.image = image; screenView?.needsDisplay = true
    }

    private func beginPhoneFileDrag(uri: String, name: String, from point: NSPoint, view: NSView?) {
        guard let view else { return }
        let delegate = PhoneFilePromise(uri: uri, fileName: name) { [weak self] uri, name, destination, completion in
            self?.requestPhoneFile(uri: uri, name: name, destination: destination, completion: completion)
        }
        phoneFilePromise = delegate
        let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: delegate)
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.draggingFrame = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        guard let event = NSApp.currentEvent else { return }
        let session = view.beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func requestPhoneFile(uri: String, name: String, destination: URL, completion: @escaping (Error?) -> Void) {
        let transferID = "drag-" + UUID().uuidString
        try? FileManager.default.removeItem(at: destination)
        pendingDownloads[transferID] = (destination: destination, completion: completion, name: name)
        socket.send(["type":"file_drag_pull", "transfer_id":transferID, "uri":uri, "name":name])
    }

    private func handlePhoneFileChunk(_ o: [String: Any]) {
        guard let id = o["transfer_id"] as? String, let state = pendingDownloads[id], let b64 = o["data"] as? String, let data = Data(base64Encoded: b64) else { return }
        do {
            if !FileManager.default.fileExists(atPath: state.destination.path) { FileManager.default.createFile(atPath: state.destination.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: state.destination)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            pendingDownloads.removeValue(forKey: id)?.completion(error)
        }
    }

    private func handlePhoneFileEnd(_ o: [String: Any]) {
        guard let key = o["transfer_id"] as? String, let state = pendingDownloads.removeValue(forKey: key) else { return }
        if (o["success"] as? Bool) == false {
            let message = o["message"] as? String ?? "Phone could not read this file"
            state.completion(NSError(domain: "MAANFileTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        } else {
            state.completion(nil)
        }
    }

    // NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    private func setClipboardText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        clipboardChange = pb.changeCount
    }

    private func setClipboardImage(_ base64: String) {
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        clipboardChange = pb.changeCount
    }

    private func syncClipboard(){
        let pb = NSPasteboard.general; guard pb.changeCount != clipboardChange else { return }; clipboardChange = pb.changeCount
        if let text = pb.string(forType:.string) { socket.send(["type":"clipboard_text","text":text]); return }
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using:.png, properties:[:]) { socket.send(["type":"clipboard_image","data":png.base64EncodedString()]) }
    }
}

let app = NSApplication.shared; let delegate = MAANApp(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
