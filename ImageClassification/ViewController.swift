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
    lazy var mlModel = alphanote_mini()
   
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

    
    //MARK:- Init views
    override func viewDidLoad() {
        super.viewDidLoad()

//        let videoURL = URL(string: "https://hls.ssh101.com/live/Tokyo/index.m3u8")!;
        
//        let videoURL = URL(string: "http://184.72.239.149/vod/smil:BigBuckBunny.smil/playlist.m3u8")!
        let videoURL = URL(string: "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8")!
//        let videoURL = URL(string: "https://mnmedias.api.telequebec.tv/m3u8/29880.m3u8")!
        
//        let videoURL = URL(string: "https://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
//        let videoURL = URL(fileURLWithPath: Bundle.main.path(forResource: "Kengo", ofType: "MOV")!)
        player = AVPlayer(url: videoURL)
//        let playerLayer = AVPlayerLayer(player: player)
//        playerLayer.frame = self.videoView.bounds
//        self.videoView.layer.addSublayer(playerLayer)

        player.play()

        
        player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: DispatchQueue(label: "videoProcessing", qos: .background),
            using: { time in
                self.doThingsWithFaces()
        })
//
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.setUpOutput()
        }
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
            var final_image = image
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
                    
                    text.draw(in: CGRect(x: converted_rect.origin.x - converted_rect.size.width / 2.0, y: converted_rect.origin.y + converted_rect.size.height + lineWidth, width: converted_rect.size.width * 4, height: 40), withAttributes: [NSAttributedStringKey.foregroundColor: UIColor.white, NSAttributedStringKey.font: UIFont.systemFont(ofSize: 32.0)])
                    
                    
                    //get result image
                    let result=UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    final_image=result!
                }
            }
            
            //display final image
            DispatchQueue.main.async{
                self.imageView.image = final_image
            }
        }
        
        
        guard let ciimage = image.ciImage else{
            fatalError("couldn't convert uiimage to ciimage")
        }
        
        let handler=VNImageRequestHandler(ciImage: ciimage)
        DispatchQueue.global(qos: .userInteractive).async{
            do{
                try handler.perform([request])
            }catch{
                print(error)
            }
        }
    }
    
    
    func identifyFace(fromImage image: UIImage)-> alphanote_miniOutput {
        
        var predictionValue: alphanote_miniOutput!
        
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
   
}

