import CoreGraphics

/// Positions the overlay beside the cursor. Uses AppKit's bottom-left-origin coordinates.
public enum OverlayPlacement {
    /// Horizontal distance from the cursor hotspot, clearing the arrow's width.
    private static let gap: CGFloat = 16
    /// Downward shift from the hotspot, aligning with the arrow's body.
    private static let dropFromHotspot: CGFloat = 8

    public static func origin(cursor: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        var x = cursor.x + gap
        if x + size.width > screen.maxX {
            x = cursor.x - gap - size.width
        }

        let y = cursor.y - dropFromHotspot - size.height / 2
        let clampedY = min(max(y, screen.minY), screen.maxY - size.height)
        return CGPoint(x: x, y: clampedY)
    }
}
