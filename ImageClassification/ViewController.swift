import UIKit
import CoreML
import Vision
import ImageIO
import ARKit
import AVKit
import AVFoundation


class ImageClassificationViewController: UIViewController, ARSCNViewDelegate {
    // MARK: - IBOutlets        
    @IBOutlet weak var classificationLabel: UILabel!
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    
    
    // MARK: - Image Classification
    @objc var player: AVPlayer!
    var videoOutput: AVPlayerItemVideoOutput?
    private var scanTimer: Timer?
    private var scannedFaceViews = [UIView]()
    lazy var mlModel = alphanote_mini()
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, let item = object as? AVPlayerItem
            else { return }
        
        switch keyPath {
        case #keyPath(AVPlayerItem.status):
            if item.status == .readyToPlay {
                self.setUpOutput()
            }
            break
        default: break
        }
    }
    
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
    
    func doThingsWithFaces() {
        guard let buffer = getNewFrame() else { return }
        // some CoreML / Vision things on that.
        // There are numerous examples with this
        
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let image = UIImage(ciImage: ciImage)
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            self.detectFaces(forImage: image)
            
//             Resnet50 expects an image 224 x 224, so we should resize and crop the source image
                        let inputImageSize: CGFloat = 224.0
                        let minLen = min(image.size.width, image.size.height)
                        let resizedImage = image.resize(to: CGSize(width: inputImageSize * image.size.width / minLen, height: inputImageSize * image.size.height / minLen))
                        let cropedToSquareImage = resizedImage.cropToSquare()
            guard let pixelBuffer = cropedToSquareImage?.pixelBuffer() else {
                fatalError()
            }
//
            DispatchQueue.main.async {
                if let prediction = try? self.mlModel.prediction(image: pixelBuffer) {
                    print(prediction.label)
                    self.classificationLabel.text = prediction.label
                }
            }
        }
    }

    
    //MARK:- Init views
    override func viewDidLoad() {
        super.viewDidLoad()

//        let videoURL = URL(string: "https://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
        let videoURL = URL(fileURLWithPath: Bundle.main.path(forResource: "Kengo", ofType: "MOV")!)
        player = AVPlayer(url: videoURL)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = .zero
        self.videoView.layer.addSublayer(playerLayer)
        
        player.play()
        
        player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: DispatchQueue(label: "videoProcessing", qos: .background),
            using: { time in
                self.doThingsWithFaces()
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.setUpOutput()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.view.bringSubview(toFront: classificationLabel)
//        self.view.bringSubview(toFront: imageView)
    }
    
    
    func detectFaces(forImage image: UIImage) {
        let request = VNDetectFaceRectanglesRequest{request, error in
            var final_image = image
            
            if let results = request.results as? [VNFaceObservation]{
                print(results.count, "faces found")
                for face_obs in results{
                    //draw original image
                    UIGraphicsBeginImageContextWithOptions(final_image.size, false, 1.0)
                    final_image.draw(in: CGRect(x: 0, y: 0, width: final_image.size.width, height: final_image.size.height))
                    
                    //get face rect
                    var rect=face_obs.boundingBox
                    let tf=CGAffineTransform.init(scaleX: 1, y: -1).translatedBy(x: 0, y: -final_image.size.height)
                    let ts=CGAffineTransform.identity.scaledBy(x: final_image.size.width, y: final_image.size.height)
                    let converted_rect=rect.applying(ts).applying(tf)
                    
                    //draw face rect on image
                    let c=UIGraphicsGetCurrentContext()!
                    c.setStrokeColor(UIColor.red.cgColor)
                    c.setLineWidth(0.01*final_image.size.width)
                    c.stroke(converted_rect)
                    
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

}

