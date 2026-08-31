import BattleLineCore
import SwiftUI
import Testing
import UIKit
@testable import BattleLine

@Suite("Battlefield scrolling", .serialized)
@MainActor
struct MatchViewScrollingTests {
    @Test("Scrolling to either end preserves offscreen play and claim targets", arguments: [false, true])
    func scrollingPreservesTargets(claiming: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let model = MatchViewModel.preview()
        if claiming {
            model.phase = .claiming
            for index in model.lines.indices {
                model.lines[index].isClaimable = true
            }
        }
        var submittedAction: GameAction?
        model.setActionHandler { submittedAction = $0 }
        let host = UIHostingController(rootView: MatchView(model: model, leaveMatch: {}))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        try await waitUntil {
            host.view.layoutIfNeeded()
            return battlefield(in: host.view) != nil
        }
        let scroll = try #require(battlefield(in: host.view))
        // Wait for the initial scroll-to-middle request to settle before selecting.
        try await waitUntil { scroll.contentOffset.x > 1 }
        if claiming {
            model.toggleClaim(model.lines[3])
            model.toggleClaim(model.lines[1])
        } else {
            model.selectCard(model.hand[0])
            model.selectLine(model.lines[3])
        }
        let selectedCardID = model.selectedCardID
        let contentWidth = scroll.contentSize.width
        let start = -scroll.adjustedContentInset.left
        let end = contentWidth - scroll.bounds.width + scroll.adjustedContentInset.right
        #expect(end > start)

        // Exercise the real SwiftUI-backed UIScrollView, not an isolated model setter.
        for offset in [start, end] {
            scroll.setContentOffset(CGPoint(x: offset, y: scroll.contentOffset.y), animated: false)
            model.notice = offset == start ? "滚动检查：起点" : "滚动检查：终点"
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            #expect(abs(scroll.contentOffset.x - offset) < 1)
            #expect(abs(scroll.contentSize.width - contentWidth) < 1)
            #expect(model.selectedCardID == selectedCardID)
            if claiming {
                #expect(model.selectedClaimIDs == [3, 1])
            } else {
                #expect(model.selectedLineID == 3)
            }
        }

        // The selected targets are now outside the right-end viewport; submission
        // must still use those targets, preserving the user's claim order as well.
        if claiming {
            model.confirmClaims()
            #expect(submittedAction == .declareClaims([
                try FlagID(validating: 3), try FlagID(validating: 1),
            ]))
        } else {
            model.confirmPlay()
            #expect(submittedAction == .play(
                card: try TroopCard(color: .red, value: 2),
                to: try FlagID(validating: 3)
            ))
        }
    }

    private func battlefield(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView,
           scroll.bounds.width > 0,
           scroll.contentSize.width > scroll.bounds.width * 2 {
            return scroll
        }
        for child in view.subviews {
            if let scroll = battlefield(in: child) { return scroll }
        }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("The hosted battlefield did not finish laying out")
        throw LayoutError.timedOut
    }

    private enum LayoutError: Error {
        case timedOut
    }
}
