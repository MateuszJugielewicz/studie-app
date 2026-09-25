import UIKit

/// App-wide navigation bar look: the plain system "‹ Back" is replaced by a round glass button
/// with a chevron, like the rest of EasySesh. Swipe-to-go-back keeps working because it's still
/// the system back button.
enum NavigationAppearance {
    static func apply() {
        let back = backImage()
        let clear: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 0.1)]

        func configure(_ appearance: UINavigationBarAppearance) {
            appearance.setBackIndicatorImage(back, transitionMaskImage: back)
            let button = UIBarButtonItemAppearance(style: .plain)
            button.normal.titleTextAttributes = clear
            button.highlighted.titleTextAttributes = clear
            button.normal.titlePositionAdjustment = UIOffset(horizontal: -1000, vertical: 0)
            appearance.backButtonAppearance = button
            appearance.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .bold)]
            appearance.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .heavy)]
        }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        configure(standard)

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        configure(edge)

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.compactScrollEdgeAppearance = edge
    }

    /// A 34 pt glass circle with a bold chevron, in light and dark variants.
    private static func backImage() -> UIImage {
        let light = render(style: .light)
        let dark = render(style: .dark)
        let asset = UIImageAsset()
        asset.register(light, with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(dark, with: UITraitCollection(userInterfaceStyle: .dark))
        return asset.image(with: .current)
            .withRenderingMode(.alwaysOriginal)
            .withAlignmentRectInsets(UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 0))
    }

    private static func render(style: UIUserInterfaceStyle) -> UIImage {
        let size = CGSize(width: 34, height: 34)
        let isDark = style == .dark
        let traits = UITraitCollection(userInterfaceStyle: style)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let circle = UIBezierPath(ovalIn: rect)
            (isDark ? UIColor.white.withAlphaComponent(0.14) : UIColor.black.withAlphaComponent(0.06)).setFill()
            circle.fill()
            (isDark ? UIColor.white.withAlphaComponent(0.22) : UIColor.black.withAlphaComponent(0.1)).setStroke()
            circle.lineWidth = 0.8
            circle.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            if let chevron = UIImage(systemName: "chevron.left", withConfiguration: config)?
                .withTintColor(UIColor.label.resolvedColor(with: traits), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - chevron.size.width) / 2 - 1, y: (size.height - chevron.size.height) / 2)
                chevron.draw(at: origin)
            }
        }
        return image
    }
}
