// AutoTest: see build.sh
import SwiftUI
import UIKit

// Test fixture for 'playcover automate': every input shows up as text that the inspector can read back

final class Model: ObservableObject {
    @Published var swiftUITaps = 0
}

struct SwiftUIPanel: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 8) {
            Button("SwiftUI button") { model.swiftUITaps += 1 }
                .accessibilityIdentifier("swiftuiButton")
            Text("SwiftUI taps: \(model.swiftUITaps)")
                .accessibilityIdentifier("swiftuiCounter")
        }
    }
}

final class ViewController: UIViewController, UITextFieldDelegate {
    let counter = UILabel()
    let typed = UILabel()
    let gesture = UILabel()
    let field = UITextField()
    let model = Model()
    var taps = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let button = UIButton(type: .system)
        button.setTitle("Tap me", for: .normal)
        button.accessibilityIdentifier = "tapButton"
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        counter.text = "Taps: 0"
        counter.accessibilityIdentifier = "counter"

        field.placeholder = "Type here"
        field.borderStyle = .roundedRect
        field.accessibilityIdentifier = "field"
        field.addTarget(self, action: #selector(edited), for: .editingChanged)
        field.delegate = self
        typed.text = "Typed: "
        typed.accessibilityIdentifier = "typed"

        let pad = UILabel()
        pad.text = "Swipe or hold here"
        pad.textAlignment = .center
        pad.backgroundColor = .secondarySystemBackground
        pad.isUserInteractionEnabled = true
        pad.accessibilityIdentifier = "pad"
        for direction in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            pad.addGestureRecognizer(swipe)
        }
        pad.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(held(_:))))
        gesture.text = "Gesture: none"
        gesture.accessibilityIdentifier = "gesture"

        let hosting = UIHostingController(rootView: SwiftUIPanel(model: model))
        addChild(hosting)

        let stack = UIStackView(arrangedSubviews: [button, counter, field, typed, pad, gesture, hosting.view])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        hosting.didMove(toParent: self)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 320),
            pad.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    @objc func tapped() {
        taps += 1
        counter.text = "Taps: \(taps)"
    }

    @objc func edited() {
        typed.text = "Typed: \(field.text ?? "")"
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        typed.text = "Typed: \(field.text ?? "") (return)"
        textField.resignFirstResponder()
        return true
    }

    @objc func swiped(_ recognizer: UISwipeGestureRecognizer) {
        let names: [UInt: String] = [1: "right", 2: "left", 4: "up", 8: "down"]
        gesture.text = "Gesture: swipe \(names[recognizer.direction.rawValue] ?? "?")"
    }

    @objc func held(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            gesture.text = "Gesture: long press"
        }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
