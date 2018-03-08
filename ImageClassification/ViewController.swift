import UIKit
import CoreML
import Vision
import ImageIO
import ARKit
import AVKit
import AVFoundation

class ImageClassificationViewController: UIViewController, ARSCNViewDelegate {
    // MARK: - IBOutlets
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    
    // MARK: - Image Classification
    @objc var player: AVPlayer!
    var videoOutput: AVPlayerItemVideoOutput?
    private var scanTimer: Timer?
    lazy var mlModel = AlphanoteNew()
    let PREPAREDATA = false
    
    func setUpOutput() {
        let videoItem = player.currentItem!
        if videoItem.status != AVPlayerItemStatus.readyToPlay {
            // see https://forums.developer.apple.com/thread/27589#128476
            return
        }
        
        let pixelBuffAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ] as [String: Any]
        
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBuffAttributes)
        videoItem.add(videoOutput)
        self.videoOutput = videoOutput
    }
    
    func getNewFrame() -> CVPixelBuffer? {
        guard let videoOutput = videoOutput, let currentItem = player.currentItem else { return nil }
        
        let time = currentItem.currentTime()
        if !videoOutput.hasNewPixelBuffer(forItemTime: time) { return nil }
        guard let buffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
            else { return nil }
        return buffer
    }
    
    @objc func doThingsWithFaces() {
        guard let buffer = getNewFrame() else { return }
        // some CoreML / Vision things on that.
        // There are numerous examples with this
        
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let image = UIImage(ciImage: ciImage)
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            self.detectFaces(forImage: image)
            

        }
    }

    @objc func shotVideo() {
        if let image = screenshotCMTime(cmTime: player.currentTime()) {
//            self.imageView.image = image
            detectFaces(forImage: image)
        }
    }
    
    //MARK:- Init views
    override func viewDidLoad() {
        super.viewDidLoad()

//        let videoURL = URL(string: "https://hls.ssh101.com/live/Tokyo/index.m3u8")!;
        
//        let videoURL = URL(string: "http://184.72.239.149/vod/smil:BigBuckBunny.smil/playlist.m3u8")!
//        let videoURL = URL(string: "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8")!
//        let videoURL = URL(string: "https://mnmedias.api.telequebec.tv/m3u8/29880.m3u8")!
        let videoURL = URL(string: "http://ec2-13-115-35-165.ap-northeast-1.compute.amazonaws.com/vod/3.mp4")!
//        let videoURL = URL(string: "https://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
//        let videoURL = URL(fileURLWithPath: Bundle.main.path(forResource: "Kengo", ofType: "MOV")!)
        player = AVPlayer(url: videoURL)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = self.view.bounds
        self.view.layer.addSublayer(playerLayer)
        self.view.bringSubview(toFront: imageView)
        player.play()
        
        scanTimer = Timer.scheduledTimer(timeInterval: (1/240), target: self, selector: #selector(shotVideo), userInfo: nil, repeats: true)
        
//        player.addPeriodicTimeObserver(
//            forInterval: CMTime(value: 1, timescale: 120),
//            queue: DispatchQueue(label: "videoProcessing", qos: .background),
//            using: { time in
//                self.doThingsWithFaces()
//
//        })
////
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            self.setUpOutput()
//        }
    }
    
    func screenshotCMTime(cmTime: CMTime)  -> (UIImage)?
    {
        guard let player = player,let asset = player.currentItem?.asset else
        {
            return nil
        }
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        var image: UIImage?
        var timePicture = kCMTimeZero
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = kCMTimeZero
        imageGenerator.requestedTimeToleranceBefore = kCMTimeZero
        do {
            let ref = try imageGenerator.copyCGImage(at: cmTime, actualTime: &timePicture)
            
            image = UIImage(cgImage: ref)
        }catch {
        }
        return image
    }
    
    func crop(image: UIImage, rect: CGRect)-> UIImage? {
        UIGraphicsBeginImageContextWithOptions(rect.size, false, image.scale)
        image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        let cropped_image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return cropped_image
    }
    
    func detectFaces(forImage image: UIImage) {
        let request = VNDetectFaceRectanglesRequest{request, error in
            var final_image = image//self.imageWithPixelSize(size: CGSize(width: image.size.width, height: image.size.height))
            
            let lineWidth = 0.01*final_image.size.width
            if let results = request.results as? [VNFaceObservation]{
                for face_obs in results{
                    
                    //draw original image
                    UIGraphicsBeginImageContextWithOptions(final_image.size, false, 1.0)
                    final_image.draw(in: CGRect(x: 0, y: 0, width: final_image.size.width, height: final_image.size.height))
                    
                    //get face rect
                    let rect=face_obs.boundingBox
                    let tf=CGAffineTransform.init(scaleX: 1, y: -1).translatedBy(x: 0, y: -final_image.size.height)
                    let ts=CGAffineTransform.identity.scaledBy(x: final_image.size.width, y: final_image.size.height)
                    let converted_rect = rect.applying(ts).applying(tf)
                    
                    // Get face to identify
                    let uiImage = self.crop(image: image, rect: converted_rect)!
                    if self.PREPAREDATA {
                        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                    }
                    else {
                        let prediction = self.identifyFace(fromImage: uiImage)
                        
                        //draw face rect on image
                        let c=UIGraphicsGetCurrentContext()!
                        c.setStrokeColor(UIColor.red.cgColor)
                        c.setLineWidth(lineWidth)
                        c.stroke(converted_rect)
                        
                        // Draw text
                        let probability = prediction.labelProbability.filter({ $0.key == prediction.label}).first!
                        
                        
                        var text = String(format: "  %.2f%% %@", probability.value * 100, prediction.label)
                        if probability.value < 0.6 {
                            text = "Unknown"
                        }
                        
                        text.draw(in: CGRect(x: converted_rect.origin.x, y: converted_rect.origin.y + converted_rect.size.height + lineWidth, width: converted_rect.size.width * 4, height: 40), withAttributes: [NSAttributedStringKey.foregroundColor: UIColor.white, NSAttributedStringKey.font: UIFont.systemFont(ofSize: 32.0)])
                        
                        
                    }
                    
                    //get result image
                    let result = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    final_image=result!
                }
            }
            
            //display final image
            DispatchQueue.main.async{
                self.imageView.image = final_image
            }
        }
        
        
        let ciimage = CIImage(cgImage: image.cgImage!)
//        guard let ciimage = CIImage(cgImage: image.cgImage!) else{
//            fatalError("couldn't convert uiimage to ciimage")
//        }
        
        let handler=VNImageRequestHandler(ciImage: ciimage)
        DispatchQueue.global(qos: .userInteractive).async{
            do{
                try handler.perform([request])
            }catch{
                print(error)
            }
        }
    }
    
    
    func identifyFace(fromImage image: UIImage)-> AlphanoteNewOutput {
        
        var predictionValue: AlphanoteNewOutput!
        
        // Resnet50 expects an image 224 x 224, so we should resize and crop the source image
        let inputImageSize: CGFloat = 224.0
        let minLen = min(image.size.width, image.size.height)
        let resizedImage = image.resize(to: CGSize(width: inputImageSize * image.size.width / minLen, height: inputImageSize * image.size.height / minLen))
        let cropedToSquareImage = resizedImage.cropToSquare()
        guard let pixelBuffer = cropedToSquareImage?.pixelBuffer() else {
            fatalError()
        }
        
        if let prediction = try? self.mlModel.prediction(image: pixelBuffer) {
            predictionValue = prediction
        }
        return predictionValue
    }
    
    func imageWithPixelSize(size: CGSize, filledWithColor color: UIColor = UIColor.clear, opaque: Bool = false) -> UIImage {
        return imageWithSize(size: size, filledWithColor: color, scale: 1.0, opaque: opaque)
    }
    
    func imageWithSize(size: CGSize, filledWithColor color: UIColor = UIColor.clear, scale: CGFloat = 0.0, opaque: Bool = false) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        color.set()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image!
    }
   
    
    func image(fromVideo videoURL: URL?, atTime time: TimeInterval) -> UIImage? {
        // courtesy of memmons
        // http://stackoverflow.com/questions/1518668/grabbing-the-first-frame-of-a-video-from-uiimagepickercontroller
        let asset = AVURLAsset(url: videoURL!, options: nil)
        
        let assetIG = AVAssetImageGenerator(asset: asset)
        assetIG.appliesPreferredTrackTransform = true
        assetIG.apertureMode = .encodedPixels
        var thumbnailImageRef: CGImage? = nil
        let thumbnailImageTime = CFTimeInterval(time)
        let igError: Error? = nil
        
        thumbnailImageRef = try! assetIG.copyCGImage(at: CMTimeMake(Int64(thumbnailImageTime), 60), actualTime: nil)
        
        var image = UIImage(cgImage: thumbnailImageRef!)
        
        return image
    }
}



