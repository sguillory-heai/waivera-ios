import Testing

@testable import ChatFeature

struct InboxOrderHoldTests {
    @Test("Without a hold the live order shows and nothing waits")
    func live() {
        let hold = InboxOrderHold()
        #expect(hold.arrange([3, 1, 2]) == ([3, 1, 2], false))
    }

    @Test("A held order keeps rows in place and reports the waiting move")
    func heldReorder() {
        var hold = InboxOrderHold()
        hold.hold([1, 2, 3])
        let arranged = hold.arrange([3, 1, 2])
        #expect(arranged.order == [1, 2, 3])
        #expect(arranged.hasPending)
    }

    @Test("New conversations wait; removed ones disappear at once")
    func heldInsertAndRemove() {
        var hold = InboxOrderHold()
        hold.hold([1, 2, 3])
        #expect(hold.arrange([4, 1, 3]) == ([1, 3], true))
        #expect(hold.arrange([1, 3]) == ([1, 3], false))
    }

    @Test("Releasing shows the live order; rebasing re-takes it while held")
    func releaseAndRebase() {
        var hold = InboxOrderHold()
        hold.rebase([9])
        #expect(!hold.isHolding)
        hold.hold([1, 2])
        hold.hold([2, 1])
        #expect(hold.arrange([2, 1]).order == [1, 2])
        hold.rebase([2, 1])
        #expect(hold.arrange([2, 1]) == ([2, 1], false))
        hold.release()
        #expect(hold.arrange([5, 2]) == ([5, 2], false))
    }
}
