import AppKit
import CoreImage

enum QRCodeRenderer {
    static func image(text: String) throws -> NSImage {
        guard !text.isEmpty, text.utf8.count <= 2000 else { throw UserFacingError("请输入文字或链接，内容最多支持 2000 字节。") }
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        guard let output = filter?.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { throw UserFacingError("二维码生成失败，请减少内容后重试。") }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
