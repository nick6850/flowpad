import Foundation

enum GestureCatalog {
    static let all: [GestureDefinition] = [
        .init(id: .oneTopLeftTap, title: "Tap top-left corner", category: .oneFinger, pattern: .cornerTap(.topLeft), symbol: "arrow.up.left.and.arrow.down.right"),
        .init(id: .oneTopRightTap, title: "Tap top-right corner", category: .oneFinger, pattern: .cornerTap(.topRight), symbol: "arrow.up.right.and.arrow.down.left"),
        .init(id: .oneBottomLeftTap, title: "Tap bottom-left corner", category: .oneFinger, pattern: .cornerTap(.bottomLeft), symbol: "arrow.down.left"),
        .init(id: .oneBottomRightTap, title: "Tap bottom-right corner", category: .oneFinger, pattern: .cornerTap(.bottomRight), symbol: "arrow.down.right"),
        .init(id: .oneTopLeftClick, title: "Click top-left corner", category: .oneFinger, pattern: .cornerClick(.topLeft), symbol: "cursorarrow.click.2"),
        .init(id: .oneTopRightClick, title: "Click top-right corner", category: .oneFinger, pattern: .cornerClick(.topRight), symbol: "cursorarrow.click.2"),
        .init(id: .oneBottomLeftClick, title: "Click bottom-left corner", category: .oneFinger, pattern: .cornerClick(.bottomLeft), symbol: "cursorarrow.click.2"),
        .init(id: .oneBottomRightClick, title: "Click bottom-right corner", category: .oneFinger, pattern: .cornerClick(.bottomRight), symbol: "cursorarrow.click.2"),

        .init(id: .twoLeftEdgeSwipe, title: "Swipe two from left edge", category: .twoFinger, pattern: .edgeSwipeLeft, symbol: "arrow.right.to.line"),
        .init(id: .onePlusTopLeft, title: "Rest one, tap top-left corner", category: .twoFinger, pattern: .restOneCornerTap(.topLeft), symbol: "arrow.up.left.circle"),
        .init(id: .onePlusTopRight, title: "Rest one, tap top-right corner", category: .twoFinger, pattern: .restOneCornerTap(.topRight), symbol: "arrow.up.right.circle"),
        .init(id: .onePlusLeft, title: "Rest one, tap left", category: .twoFinger, pattern: .restOneTap(side: .left, near: false), symbol: "hand.tap"),
        .init(id: .onePlusRight, title: "Rest one, tap right", category: .twoFinger, pattern: .restOneTap(side: .right, near: false), symbol: "hand.tap"),
        .init(id: .onePlusLeftNear, title: "Rest one, tap near left", category: .twoFinger, pattern: .restOneTap(side: .left, near: true), symbol: "hand.tap"),
        .init(id: .onePlusRightNear, title: "Rest one, tap near right", category: .twoFinger, pattern: .restOneTap(side: .right, near: true), symbol: "hand.tap"),
        .init(id: .onePlusSwipeDownLeft, title: "Rest one, swipe down left", category: .twoFinger, pattern: .restOneSwipe(side: .left, direction: .down), symbol: "arrow.down"),
        .init(id: .onePlusSwipeUpLeft, title: "Rest one, swipe up left", category: .twoFinger, pattern: .restOneSwipe(side: .left, direction: .up), symbol: "arrow.up"),
        .init(id: .onePlusSwipeDownRight, title: "Rest one, swipe down right", category: .twoFinger, pattern: .restOneSwipe(side: .right, direction: .down), symbol: "arrow.down"),
        .init(id: .onePlusSwipeUpRight, title: "Rest one, swipe up right", category: .twoFinger, pattern: .restOneSwipe(side: .right, direction: .up), symbol: "arrow.up"),

        .init(id: .threeClick, title: "Click with three", category: .threeFinger, pattern: .multiClick(count: 3), symbol: "cursorarrow.click"),
        .init(id: .threeTap, title: "Tap with three", category: .threeFinger, pattern: .multiTap(count: 3), symbol: "hand.tap"),
        .init(id: .twoPlusCenter, title: "Rest two, tap between", category: .threeFinger, pattern: .restTwoTap(.center), symbol: "circle.grid.cross"),
        .init(id: .twoPlusLeft, title: "Rest two, tap left", category: .threeFinger, pattern: .restTwoTap(.left), symbol: "arrow.left.circle"),
        .init(id: .twoPlusRight, title: "Rest two, tap right", category: .threeFinger, pattern: .restTwoTap(.right), symbol: "arrow.right.circle"),
        .init(id: .onePlusTwoSwipeDownLeft, title: "Rest one, swipe two down left", category: .threeFinger, pattern: .restOneTwoSwipe(side: .left, direction: .down), symbol: "arrow.down.left"),
        .init(id: .onePlusTwoSwipeUpLeft, title: "Rest one, swipe two up left", category: .threeFinger, pattern: .restOneTwoSwipe(side: .left, direction: .up), symbol: "arrow.up.left"),
        .init(id: .onePlusTwoSwipeDownRight, title: "Rest one, swipe two down right", category: .threeFinger, pattern: .restOneTwoSwipe(side: .right, direction: .down), symbol: "arrow.down.right"),
        .init(id: .onePlusTwoSwipeUpRight, title: "Rest one, swipe two up right", category: .threeFinger, pattern: .restOneTwoSwipe(side: .right, direction: .up), symbol: "arrow.up.right"),
        .init(id: .threeSwipeUp, title: "Swipe up with three", category: .threeFinger, pattern: .multiSwipe(count: 3, direction: .up), symbol: "arrow.up"),
        .init(id: .threeSwipeDown, title: "Swipe down with three", category: .threeFinger, pattern: .multiSwipe(count: 3, direction: .down), symbol: "arrow.down"),
        .init(id: .threeSwipeLeft, title: "Swipe left with three", category: .threeFinger, pattern: .multiSwipe(count: 3, direction: .left), symbol: "arrow.left"),
        .init(id: .threeSwipeRight, title: "Swipe right with three", category: .threeFinger, pattern: .multiSwipe(count: 3, direction: .right), symbol: "arrow.right"),
        .init(id: .threeToOne, title: "Three to one", category: .threeFinger, pattern: .collapseToOne(count: 3, direction: nil), symbol: "circle.grid.3x3"),
        .init(id: .threeToOneUp, title: "Three to one, slide up", category: .threeFinger, pattern: .collapseToOne(count: 3, direction: .up), symbol: "arrow.up"),
        .init(id: .threeToOneDown, title: "Three to one, slide down", category: .threeFinger, pattern: .collapseToOne(count: 3, direction: .down), symbol: "arrow.down"),
        .init(id: .threeToOneLeft, title: "Three to one, slide left", category: .threeFinger, pattern: .collapseToOne(count: 3, direction: .left), symbol: "arrow.left"),
        .init(id: .threeToOneRight, title: "Three to one, slide right", category: .threeFinger, pattern: .collapseToOne(count: 3, direction: .right), symbol: "arrow.right"),

        .init(id: .fourClick, title: "Click with four", category: .fourFinger, pattern: .multiClick(count: 4), symbol: "cursorarrow.click"),
        .init(id: .fourTap, title: "Tap with four", category: .fourFinger, pattern: .multiTap(count: 4), symbol: "hand.tap"),
        .init(id: .threePlusLeft, title: "Rest three, tap left", category: .fourFinger, pattern: .restThreeTap(.left), symbol: "arrow.left.circle"),
        .init(id: .threePlusRight, title: "Rest three, tap right", category: .fourFinger, pattern: .restThreeTap(.right), symbol: "arrow.right.circle"),
        .init(id: .fourSwipeUp, title: "Swipe up with four", category: .fourFinger, pattern: .multiSwipe(count: 4, direction: .up), symbol: "arrow.up"),
        .init(id: .fourSwipeDown, title: "Swipe down with four", category: .fourFinger, pattern: .multiSwipe(count: 4, direction: .down), symbol: "arrow.down"),
        .init(id: .fourSwipeLeft, title: "Swipe left with four", category: .fourFinger, pattern: .multiSwipe(count: 4, direction: .left), symbol: "arrow.left"),
        .init(id: .fourSwipeRight, title: "Swipe right with four", category: .fourFinger, pattern: .multiSwipe(count: 4, direction: .right), symbol: "arrow.right"),
        .init(id: .fourToOne, title: "Four to one", category: .fourFinger, pattern: .collapseToOne(count: 4, direction: nil), symbol: "circle.grid.3x3.fill"),
        .init(id: .fourToOneUp, title: "Four to one, slide up", category: .fourFinger, pattern: .collapseToOne(count: 4, direction: .up), symbol: "arrow.up"),
        .init(id: .fourToOneDown, title: "Four to one, slide down", category: .fourFinger, pattern: .collapseToOne(count: 4, direction: .down), symbol: "arrow.down"),
        .init(id: .fourToOneLeft, title: "Four to one, slide left", category: .fourFinger, pattern: .collapseToOne(count: 4, direction: .left), symbol: "arrow.left"),
        .init(id: .fourToOneRight, title: "Four to one, slide right", category: .fourFinger, pattern: .collapseToOne(count: 4, direction: .right), symbol: "arrow.right"),

        .init(id: .fiveClick, title: "Click with five", category: .fiveFinger, pattern: .multiClick(count: 5), symbol: "cursorarrow.click"),
        .init(id: .fiveToOne, title: "Five to one", category: .fiveFinger, pattern: .collapseToOne(count: 5, direction: nil), symbol: "circle.grid.3x3.fill"),
        .init(id: .fiveToOneUp, title: "Five to one, slide up", category: .fiveFinger, pattern: .collapseToOne(count: 5, direction: .up), symbol: "arrow.up"),
        .init(id: .fiveToOneDown, title: "Five to one, slide down", category: .fiveFinger, pattern: .collapseToOne(count: 5, direction: .down), symbol: "arrow.down"),
        .init(id: .fiveToOneLeft, title: "Five to one, slide left", category: .fiveFinger, pattern: .collapseToOne(count: 5, direction: .left), symbol: "arrow.left"),
        .init(id: .fiveToOneRight, title: "Five to one, slide right", category: .fiveFinger, pattern: .collapseToOne(count: 5, direction: .right), symbol: "arrow.right"),

        .init(id: .oneTopLeftForce, title: "Force touch top-left corner", category: .forceTouch, pattern: .forceTouch(count: 1, corner: .topLeft), symbol: "circle.circle"),
        .init(id: .oneTopRightForce, title: "Force touch top-right corner", category: .forceTouch, pattern: .forceTouch(count: 1, corner: .topRight), symbol: "circle.circle"),
        .init(id: .oneBottomLeftForce, title: "Force touch bottom-left corner", category: .forceTouch, pattern: .forceTouch(count: 1, corner: .bottomLeft), symbol: "circle.circle"),
        .init(id: .oneBottomRightForce, title: "Force touch bottom-right corner", category: .forceTouch, pattern: .forceTouch(count: 1, corner: .bottomRight), symbol: "circle.circle"),
        .init(id: .oneForce, title: "Force touch with one", category: .forceTouch, pattern: .forceTouch(count: 1, corner: nil), symbol: "circle.circle.fill"),
        .init(id: .threeForce, title: "Force touch with three", category: .forceTouch, pattern: .forceTouch(count: 3, corner: nil), symbol: "circle.grid.3x3"),
        .init(id: .fourForce, title: "Force touch with four", category: .forceTouch, pattern: .forceTouch(count: 4, corner: nil), symbol: "circle.grid.3x3.fill")
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definitions(in category: GestureCategory) -> [GestureDefinition] {
        all.filter { $0.category == category }
    }
}
