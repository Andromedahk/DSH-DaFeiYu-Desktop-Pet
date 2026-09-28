import AppKit

// Head-less modes first so they never open a window.
if Diagnostics.wantsRun() {
    exit(Diagnostics.run())
}

let app = NSApplication.shared
let controller = PetController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
