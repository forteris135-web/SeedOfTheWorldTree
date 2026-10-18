// 배경 지우기 (맥의 Vision 프레임워크, Finder "배경 제거"와 같은 기술).
// 사용: swift tools/remove_bg.swift 입력.png 출력.png
import Foundation
import Vision
import CoreImage

let args = CommandLine.arguments
guard args.count >= 3 else { print("사용: remove_bg.swift 입력 출력"); exit(1) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
guard let image = CIImage(contentsOf: inURL) else { print("못 읽음"); exit(2) }
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: image, options: [:])
do {
    try handler.perform([request])
} catch {
    print("Vision 실패: \(error)"); exit(3)
}
guard let result = request.results?.first else { print("피사체를 못 찾음"); exit(4) }
let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
let mask = CIImage(cvPixelBuffer: maskBuffer)
let blend = CIFilter(name: "CIBlendWithMask")!
blend.setValue(image, forKey: kCIInputImageKey)
blend.setValue(CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
blend.setValue(mask, forKey: kCIInputMaskImageKey)
let output = blend.outputImage!.cropped(to: image.extent)
let ctx = CIContext()
try ctx.writePNGRepresentation(of: output, to: outURL, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("저장: \(outURL.path)")
