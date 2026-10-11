//
//  bookingcodecard.swift
//  shareplate
//
//  big booking number plus branded qr so neighbors match
//  the same code at handoff
//

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct BookingCodeCard: View {
    let code: String
    var caption: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Booking")
                    .font(AppFont.captionBold)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text(code)
                    .font(AppFont.display)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.primaryText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Text(caption)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BookingQRMark(code: code, size: 120)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Booking \(code)"))
    }
}

struct BookingQRMark: View {
    let code: String
    var size: CGFloat = 120

    private var payload: String {
        "shareplate:booking:\(code)"
    }

    var body: some View {
        ZStack {
            if let image = BookingQRGenerator.image(for: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            }

            SharePlateLogoView(size: size * 0.24)
        }
        .frame(width: size, height: size)
        .background(Color(hex: 0xF7F4EA))
        .overlay { scannerFrame }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .boxBorder(Theme.Palette.primaryGreen.opacity(0.4), radius: Theme.Radius.card)
        .accessibilityHidden(true)
    }

    private var scannerFrame: some View {
        let inset = size * 0.06
        let arm = size * 0.16
        return Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: inset, dy: inset)
            let stroke = StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter)
            var path = Path()

            path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

            path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))

            path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))

            context.stroke(path, with: .color(Theme.Palette.primaryGreen), style: stroke)
        }
        .allowsHitTesting(false)
    }
}

enum BookingQRGenerator {
    private static let context = CIContext()

    static func image(for payload: String) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(payload.utf8)
        qr.correctionLevel = "H"
        guard let output = qr.outputImage else { return nil }

        let scale = max(12, 240 / max(output.extent.width, 1))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let colorize = CIFilter.falseColor()
        colorize.inputImage = scaled
        colorize.color0 = CIColor(red: 0.18, green: 0.49, blue: 0.20)
        colorize.color1 = CIColor(red: 0.97, green: 0.96, blue: 0.92)
        guard let colored = colorize.outputImage,
              let cgImage = context.createCGImage(colored, from: colored.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
