#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public extension View {
        /// Keeps the edge swipe that goes back on a screen whose system navigation bar is hidden
        /// for the plum top bar. UIKit turns the swipe off with the bar; this hands the swipe a
        /// delegate that allows it whenever there is a screen to go back to.
        func swipeBackEnabled() -> some View {
            background(SwipeBackInstaller().frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }

    /// One shared delegate for every navigation stack: it reads the stack from the gesture's view,
    /// so it holds no state and is never released while a stack still points at it (the gesture
    /// keeps only a weak reference).
    @MainActor
    private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
        static let shared = SwipeBackDelegate()

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = gestureRecognizer.view?.next as? UINavigationController else { return false }
            // At the root there is nothing to go back to, and a swipe there would freeze the stack.
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }
    }

    private struct SwipeBackInstaller: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> InstallerController {
            InstallerController()
        }

        func updateUIViewController(_ controller: InstallerController, context: Context) {}

        final class InstallerController: UIViewController {
            override func didMove(toParent parent: UIViewController?) {
                super.didMove(toParent: parent)
                install()
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                install()
            }

            private func install() {
                navigationController?.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
            }
        }
    }
#endif
