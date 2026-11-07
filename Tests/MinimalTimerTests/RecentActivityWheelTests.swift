import Testing
@testable import MinimalTimer

@Test
func wheelMapsPointerDirectionsToRecentActivityOrder() {
    #expect(WheelGeometry.selection(x: 0, y: 80, count: 4) == 0)
    #expect(WheelGeometry.selection(x: 80, y: 0, count: 4) == 1)
    #expect(WheelGeometry.selection(x: 0, y: -80, count: 4) == 2)
    #expect(WheelGeometry.selection(x: -80, y: 0, count: 4) == 3)
    #expect(WheelGeometry.selection(x: -8, y: 80, count: 4) == 0)

    #expect(WheelGeometry.selection(x: 75, y: -44, count: 3) == 1)
    #expect(WheelGeometry.selection(x: -75, y: -44, count: 3) == 2)
    #expect(WheelGeometry.selection(x: 0, y: -80, count: 2) == 1)
    #expect(WheelGeometry.selection(x: -80, y: 0, count: 1) == 0)
    #expect(WheelGeometry.selection(x: 12, y: 12, count: 4) == nil)
    #expect(WheelGeometry.selection(x: 0, y: 80, count: 0) == nil)
}
