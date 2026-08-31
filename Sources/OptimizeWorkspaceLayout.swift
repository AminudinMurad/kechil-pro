import CoreGraphics

/// Shared split-view geometry for the two Optimize routes.
///
/// The dashboard keeps a fixed 940-point content width. Keeping the settings
/// column narrow and giving the output side the larger minimum makes previews
/// and batch rows readable, while the identical values keep Image Optimize and
/// Video Optimize visually consistent.
enum OptimizeWorkspaceLayout {
    static let settingsMinimumWidth: CGFloat = 250
    static let settingsIdealWidth: CGFloat = 250
    static let settingsMaximumWidth: CGFloat = 250
    static let outputMinimumWidth: CGFloat = 480
}
