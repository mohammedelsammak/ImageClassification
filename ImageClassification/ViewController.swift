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
    
    
    // MARK: - Image Classification
    @objc var player: AVPlayer!
    private var scanTimer: Timer?
    private var scannedFaceViews = [UIView]()
    
    /// - Tag: MLModelSetup
    lazy var classificationRequest: VNCoreMLRequest = {
        do {
            /*
             Use the Swift class `MobileNet` Core ML generates from the model.
             To use a different Core ML classifier model, add it to the project
             and replace `MobileNet` with that model's generated Swift class.
             */
            let model = try VNCoreMLModel(for: alphanote_mini().model)
            
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    //MARK:- Init views
    override func viewDidLoad() {
        super.viewDidLoad()

//        let videoURL = URL(string: "https://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")
        let videoURL = URL(fileURLWithPath: Bundle.main.path(forResource: "Andreas", ofType: "MOV")!)
        player = AVPlayer(url: videoURL)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = self.view.bounds
        self.videoView.layer.addSublayer(playerLayer)
        
        player.play()
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.player.currentItem)

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //scan for faces in regular intervals
        scanTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(scanForFaces), userInfo: nil, repeats: true)
        
        self.view.bringSubview(toFront: classificationLabel)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        scanTimer?.invalidate()
    }
    
    @objc
    private func scanForFaces() {
        
        //remove the test views and empty the array that was keeping a reference to them
        _ = scannedFaceViews.map { $0.removeFromSuperview() }
        scannedFaceViews.removeAll()

        //get the captured image of the ARSession's current frame
        guard let capturedImage = screenshotCMTime(cmTime: player.currentTime()) else { return }
//            guard let capturedImage = sceneView.session.currentFrame?.capturedImage else { return }
//        imageView.image = capturedImage
        let image = CIImage(image: capturedImage)!

//        let image = CIImage.init(cvPixelBuffer: capturedImage)
        
        let detectFaceRequest = VNDetectFaceRectanglesRequest { (request, error) in

            DispatchQueue.main.async {
                //Loop through the resulting faces and add a red UIView on top of them.
                if let faces = request.results as? [VNFaceObservation] {
                    if faces.count == 0 {
                        self.classificationLabel.text = "Searching for faces..."
                    }
                    for face in faces {
                        let faceFrame = self.faceFrame(from: face.boundingBox)
                        let faceView = UIView(frame: faceFrame)

                        let croppedCIimage = image.cropImage(toFace: face).rotate


                        self.updateClassifications(for: croppedCIimage)

                        faceView.backgroundColor = .clear
                        faceView.layer.borderColor = UIColor.yellow.cgColor;
                        faceView.layer.borderWidth = 2;


                        self.view.addSubview(faceView)

                        self.scannedFaceViews.append(faceView)
                    }
                }
            }

        }
        DispatchQueue.global().async {
            try? VNImageRequestHandler(ciImage: image, orientation: self.imageOrientation).perform([detectFaceRequest])
        }
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

    /// - Tag: PerformRequests
    func updateClassifications(for image: CIImage) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: image, orientation: self.imageOrientation)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                /*
                 This handler catches general image processing errors. The `classificationRequest`'s
                 completion handler `processClassifications(_:error:)` catches errors specific
                 to processing that request.
                 */
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }
    }
    
    /// Updates the UI with the results of the classification.
    /// - Tag: ProcessClassifications
    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                self.classificationLabel.text = "Unable to classify image.\n\(error!.localizedDescription)"
                return
            }
            // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
            let classifications = results as! [VNClassificationObservation]
            
            if classifications.isEmpty {
                self.classificationLabel.text = "Nothing recognized."
            } else {
                // Display top classifications ranked by confidence in the UI.
                let topClassifications = classifications.prefix(2)
                self.classificationLabel.text = String(format: "  %.2f%% %@", topClassifications[0].confidence*100, topClassifications[0].identifier)
            }
        }
    }
    
    private func faceFrame(from boundingBox: CGRect) -> CGRect {
        
        //translate camera frame to frame inside the ARSKView
        let origin = CGPoint(x: boundingBox.minX * videoView.bounds.width, y: (1 - boundingBox.maxY) * videoView.bounds.height)
        let size = CGSize(width: boundingBox.width * videoView.bounds.width, height: boundingBox.height * videoView.bounds.height)
        
        return CGRect(origin: origin, size: size)
    }
    
    //get the orientation of the image that correspond's to the current device orientation
    private var imageOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .right
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        case .unknown: fallthrough
        case .faceUp: fallthrough
        case .faceDown: fallthrough
        case .landscapeLeft: return .up
        }
    }
    
    
    @objc func playerDidFinishPlaying() {
        
        player.seek(to: kCMTimeZero)
        player.play()
        
    }
}

