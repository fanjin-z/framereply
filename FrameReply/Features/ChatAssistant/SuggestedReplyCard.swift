//
//  SuggestedReplyCard.swift
//  FrameReply
//

import SwiftUI
import UIKit

struct SuggestedReplyCard: View {
    let reply: SuggestedReply
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        SuggestedReplyTextWithCopy(
            text: reply.text,
            isCopied: isCopied,
            copyButtonIdentifier: "suggested-reply-copy-\(reply.id.uuidString)",
            onCopy: onCopy
        )
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassPanel(cornerRadius: 18)
    }
}

private struct SuggestedReplyTextWithCopy: UIViewRepresentable {
    let text: String
    let isCopied: Bool
    let copyButtonIdentifier: String
    let onCopy: () -> Void

    func makeUIView(context: Context) -> TrailingCopyTextView {
        TrailingCopyTextView()
    }

    func updateUIView(_ uiView: TrailingCopyTextView, context: Context) {
        uiView.configure(
            text: text,
            isCopied: isCopied,
            copyButtonIdentifier: copyButtonIdentifier,
            onCopy: onCopy
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: TrailingCopyTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }
        return CGSize(width: width, height: uiView.requiredHeight(for: width))
    }
}

@MainActor
private final class TrailingCopyTextView: UIView {
    private enum Metrics {
        static let copyGap: CGFloat = 10
        static let copyVerticalGap: CGFloat = 2
        static let accessibilitySpacing: CGFloat = 8
        static let minimumButtonHeight: CGFloat = 44
        static let minimumButtonWidth: CGFloat = 82
        static let buttonHorizontalInset: CGFloat = 10
        static let iconWidth: CGFloat = 13
        static let imagePadding: CGFloat = 5
        static let sizingSlack: CGFloat = 6
        static let lineSpacing: CGFloat = 5
    }

    private let textStorage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textView: UITextView
    private let copyButton = UIButton(type: .system)
    private var copyAction: () -> Void = {}
    private var text = ""
    private var isCopied = false

    override init(frame: CGRect) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        textView = UITextView(frame: .zero, textContainer: textContainer)

        super.init(frame: frame)

        isOpaque = false
        backgroundColor = .clear

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.isAccessibilityElement = true
        textView.accessibilityTraits = .staticText

        copyButton.addAction(
            UIAction { [weak self] _ in
                self?.copyAction()
            },
            for: .touchUpInside
        )
        copyButton.titleLabel?.numberOfLines = 1
        copyButton.titleLabel?.lineBreakMode = .byClipping
        copyButton.accessibilityHint = String(localized: "Copies this suggested reply")

        addSubview(textView)
        addSubview(copyButton)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: TrailingCopyTextView, _: UITraitCollection) in
            view.handleContentSizeCategoryChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        text: String,
        isCopied: Bool,
        copyButtonIdentifier: String,
        onCopy: @escaping () -> Void
    ) {
        copyAction = onCopy
        copyButton.accessibilityIdentifier = copyButtonIdentifier

        let textChanged = self.text != text
        let copiedStateChanged = self.isCopied != isCopied
        self.text = text
        self.isCopied = isCopied

        if textChanged {
            updateAttributedText()
        }
        if copiedStateChanged || copyButton.configuration == nil {
            updateButtonConfiguration()
        }

        textView.accessibilityLabel = text
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let buttonSize = copyButtonSize()
        textView.frame = bounds

        if usesAccessibilityLayout {
            textContainer.size = CGSize(width: bounds.width, height: bounds.height)
            textContainer.exclusionPaths = []
            copyButton.frame = CGRect(
                x: bounds.width - buttonSize.width,
                y: bounds.height - buttonSize.height,
                width: buttonSize.width,
                height: buttonSize.height
            )
        } else {
            let buttonFrame = CGRect(
                x: bounds.width - buttonSize.width,
                y: bounds.height - buttonSize.height,
                width: buttonSize.width,
                height: buttonSize.height
            )
            textContainer.size = bounds.size
            textContainer.exclusionPaths = [
                exclusionPath(buttonFrame: buttonFrame, containerWidth: bounds.width)
            ]
            copyButton.frame = buttonFrame
        }

        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: textStorage.length),
            actualCharacterRange: nil
        )
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }

        let buttonSize = copyButtonSize()
        let fullWidthTextHeight = measuredTextHeight(width: width, exclusionPaths: [])

        if usesAccessibilityLayout {
            return ceil(
                fullWidthTextHeight + Metrics.accessibilitySpacing + buttonSize.height
            )
        }

        let lineAdvance = bodyFont.lineHeight + Metrics.lineSpacing
        var candidateHeight = max(buttonSize.height, ceil(fullWidthTextHeight))

        for _ in 0..<128 {
            let buttonFrame = CGRect(
                x: width - buttonSize.width,
                y: candidateHeight - buttonSize.height,
                width: buttonSize.width,
                height: buttonSize.height
            )
            textContainer.size = CGSize(width: width, height: candidateHeight)
            textContainer.exclusionPaths = [
                exclusionPath(buttonFrame: buttonFrame, containerWidth: width)
            ]
            invalidateTextLayout()

            let laidOutGlyphs = layoutManager.glyphRange(for: textContainer)
            if NSMaxRange(laidOutGlyphs) >= layoutManager.numberOfGlyphs {
                return ceil(candidateHeight)
            }

            candidateHeight += lineAdvance
        }

        return ceil(fullWidthTextHeight + buttonSize.height + Metrics.accessibilitySpacing)
    }

    private func handleContentSizeCategoryChange() {
        updateAttributedText()
        updateButtonConfiguration()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var usesAccessibilityLayout: Bool {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }

    private var bodyFont: UIFont {
        roundedScaledFont(size: 17, weight: .regular, textStyle: .body)
    }

    private var buttonFont: UIFont {
        roundedScaledFont(size: 13, weight: .semibold, textStyle: .subheadline)
    }

    private func roundedScaledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: UIFont(descriptor: descriptor, size: size)
        )
    }

    private func updateAttributedText() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Metrics.lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .natural

        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor(FrameReplyColor.onSurface),
                    .paragraphStyle: paragraphStyle,
                ]
            )
        )
    }

    private func updateButtonConfiguration() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = isCopied ? String(localized: "Copied") : String(localized: "Copy")
        configuration.image = UIImage(
            systemName: isCopied ? "checkmark" : "doc.on.doc"
        )
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: Metrics.iconWidth,
            weight: .semibold
        )
        configuration.imagePadding = Metrics.imagePadding
        configuration.titleLineBreakMode = .byClipping
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor(FrameReplyColor.secondaryContainer)
            .withAlphaComponent(0.86)
        configuration.baseForegroundColor = UIColor(FrameReplyColor.primary)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Metrics.buttonHorizontalInset,
            bottom: 0,
            trailing: Metrics.buttonHorizontalInset
        )
        let configurationButtonFont = buttonFont
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var transformed = attributes
                transformed.font = configurationButtonFont
                return transformed
            }
        copyButton.configuration = configuration
        copyButton.accessibilityLabel = isCopied
            ? String(localized: "Copied")
            : String(localized: "Copy")
    }

    private func copyButtonSize() -> CGSize {
        let titleWidth = max(
            textWidth(String(localized: "Copy")),
            textWidth(String(localized: "Copied"))
        )
        let width = max(
            Metrics.minimumButtonWidth,
            ceil(
                Metrics.buttonHorizontalInset
                    + Metrics.iconWidth
                    + Metrics.imagePadding
                    + titleWidth
                    + Metrics.buttonHorizontalInset
                    + Metrics.sizingSlack
            )
        )
        let height = max(
            Metrics.minimumButtonHeight,
            ceil(buttonFont.lineHeight + 14)
        )
        return CGSize(width: width, height: height)
    }

    private func textWidth(_ value: String) -> CGFloat {
        ceil(
            (value as NSString).size(withAttributes: [.font: buttonFont]).width
        )
    }

    private func measuredTextHeight(
        width: CGFloat,
        exclusionPaths: [UIBezierPath]
    ) -> CGFloat {
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.exclusionPaths = exclusionPaths
        invalidateTextLayout()
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }

    private func exclusionPath(
        buttonFrame: CGRect,
        containerWidth: CGFloat
    ) -> UIBezierPath {
        let reservedOriginX = max(0, buttonFrame.minX - Metrics.copyGap)
        let reservedRect = CGRect(
            x: reservedOriginX,
            y: max(0, buttonFrame.minY - Metrics.copyVerticalGap),
            width: max(0, containerWidth - reservedOriginX),
            height: buttonFrame.height + Metrics.copyVerticalGap
        )
        return UIBezierPath(rect: reservedRect)
    }

    private func invalidateTextLayout() {
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: textStorage.length),
            actualCharacterRange: nil
        )
        layoutManager.ensureLayout(for: textContainer)
    }
}
