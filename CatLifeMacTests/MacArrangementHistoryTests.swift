#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacArrangementHistoryTests: XCTestCase {
    private func draft(_ x: Double) -> ArrangementDraft68 {
        .init(bowl: .init(x: x, y: 0.7), furniture: [], orientations: [:], selectedID: nil, storedID: nil, bowlSelected: true)
    }
    func testUndoRedoRoundTripAndNewEditInvalidatesRedoWithoutChangingPersistedState() {
        let editor = ArrangementEditor68()
        let a = draft(0.4), b = draft(0.5), c = draft(0.6)
        editor.begin(a); editor.end(b)
        XCTAssertEqual(editor.undo(current: b), a)
        XCTAssertTrue(editor.canRedo)
        XCTAssertEqual(editor.redo(current: a), b)
        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(editor.undo(current: b), a)
        editor.begin(a); editor.end(c)
        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(editor.undo(current: c), a)
        editor.reset()
        XCTAssertFalse(editor.canUndo); XCTAssertFalse(editor.canRedo)
    }
    func testPendingSceneCommandBlocksHistoryAndNoOpDoesNotClearRedo() {
        let editor = ArrangementEditor68(), a = draft(0.4), b = draft(0.5)
        editor.begin(a); editor.end(b); _ = editor.undo(current: b)
        editor.begin(a); editor.end(a)
        XCTAssertTrue(editor.canRedo)
        editor.pendingRequest = .init(command: .confirm(id: nil))
        XCTAssertNil(editor.redo(current: a))
        XCTAssertFalse(editor.canRedo)
        editor.pendingRequest = nil
        XCTAssertEqual(editor.redo(current: a), b)
    }
}
#endif
