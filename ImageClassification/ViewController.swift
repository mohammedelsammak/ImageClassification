import UIKit
import CoreML
import Vision
import ImageIO
import ARKit

class ImageClassificationViewController: UIViewController, ARSCNViewDelegate {
    // MARK: - IBOutlets        
    @IBOutlet weak var classificationLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    
    // MARK: - Image Classification
    
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
        
        sceneView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
        
        //scan for faces in regular intervals
        scanTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(scanForFaces), userInfo: nil, repeats: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        scanTimer?.invalidate()
        sceneView.session.pause()
    }
    
    @objc
    private func scanForFaces() {
        
        //remove the test views and empty the array that was keeping a reference to them
        _ = scannedFaceViews.map { $0.removeFromSuperview() }
        scannedFaceViews.removeAll()
        
        //get the captured image of the ARSession's current frame
        guard let capturedImage = sceneView.session.currentFrame?.capturedImage else { return }
        
        
        let image = CIImage.init(cvPixelBuffer: capturedImage)
        
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
                        
                        
                        self.sceneView.addSubview(faceView)
                        
                        self.scannedFaceViews.append(faceView)
                    }
                }
            }
            
        }
        DispatchQueue.global().async {
            try? VNImageRequestHandler(ciImage: image, orientation: self.imageOrientation).perform([detectFaceRequest])
        }
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
            print(request.observationInfo)
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
        let origin = CGPoint(x: boundingBox.minX * sceneView.bounds.width, y: (1 - boundingBox.maxY) * sceneView.bounds.height)
        let size = CGSize(width: boundingBox.width * sceneView.bounds.width, height: boundingBox.height * sceneView.bounds.height)
        
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
}

