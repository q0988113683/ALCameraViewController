//
//  CameraViewNew.swift
//  ALCameraViewController
//
//  Created by Jhuo Yu cheng on 2019/2/22.
//  Copyright © 2019 zero. All rights reserved.
//

import UIKit
import AVFoundation


protocol CameraViewDelegate {
    func photoOutput(_ image:UIImage?)
}

class CameraView : UIView{
    
    var delegate : CameraViewDelegate?
    
    var input:AVCaptureDeviceInput!
    var output:AVCapturePhotoOutput!
    var session:AVCaptureSession!
    var camera:AVCaptureDevice!
    var preview: AVCaptureVideoPreviewLayer!
    
    let cameraQueue = DispatchQueue(label: "com.zero.ALCameraViewController.Queue")
    let focusView = CropOverlay(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    
    var flash : AVCaptureDevice.FlashMode = .auto
    
    public var currentPosition = CameraGlobals.shared.defaultCameraPosition
    
    
    public func startSession() {
        
        
        session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        camera = AVCaptureDevice.default(
            AVCaptureDevice.DeviceType.builtInWideAngleCamera,
            for: AVMediaType.video,
            position: .back) // position: .front
        do {
            input = try AVCaptureDeviceInput(device: camera)
            
        } catch let error as NSError {
            print(error)
        }
        
        if(session.canAddInput(input)) {
            session.addInput(input)
        }
        
        output = AVCapturePhotoOutput()
        if(session.canAddOutput(output)) {
            session.addOutput(output)
        }
        
        cameraQueue.sync {
            session.startRunning()
            DispatchQueue.main.async() { [weak self] in
                self?.createPreview()
                self?.rotatePreview()
            }
        }
    }
    
    public func stopSession() {
        cameraQueue.sync {
            session?.stopRunning()
            preview?.removeFromSuperlayer()
            
            session = nil
            input = nil
            output = nil
            preview = nil
            camera = nil
        }
    }
    
    
    private func createPreview() {
        
        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = AVLayerVideoGravity.resizeAspectFill
        preview.frame = bounds
        
        layer.addSublayer(preview)
    }
    
    public func rotatePreview() {
        
        guard preview != nil else {
            return
        }
        switch UIApplication.shared.statusBarOrientation {
        case .portrait:
            preview?.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
            break
        case .portraitUpsideDown:
            preview?.connection?.videoOrientation = AVCaptureVideoOrientation.portraitUpsideDown
            break
        case .landscapeRight:
            preview?.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
            break
        case .landscapeLeft:
            preview?.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
            break
        default: break
        }
    }
    
    
    
    func takePicture(){
        
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = flash
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoSettings.isHighResolutionPhotoEnabled = false
        
        output?.capturePhoto(with: photoSettings, delegate: self)
    }
    
    
    
    
    public func configureFocus() {
        
        if let gestureRecognizers = gestureRecognizers {
            gestureRecognizers.forEach({ removeGestureRecognizer($0) })
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focus(gesture:)))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
        addSubview(focusView)
        
        focusView.isHidden = true
        
        let lines = focusView.horizontalLines + focusView.verticalLines + focusView.outerLines
        
        lines.forEach { line in
            line.alpha = 0
        }
    }
    
    public func configureZoom() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinch(gesture:)))
        addGestureRecognizer(pinchGesture)
    }
    
    @objc internal func focus(gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        
        guard focusCamera(toPoint: point) else {
            return
        }
        
        focusView.isHidden = false
        focusView.center = point
        focusView.alpha = 0
        focusView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        
        bringSubviewToFront(focusView)
        
        UIView.animateKeyframes(withDuration: 1.5, delay: 0, options: UIView.KeyframeAnimationOptions(), animations: {
            
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.15, animations: { [weak self] in
                self?.focusView.alpha = 1
                self?.focusView.transform = CGAffineTransform.identity
            })
            
            UIView.addKeyframe(withRelativeStartTime: 0.80, relativeDuration: 0.20, animations: { [weak self] in
                self?.focusView.alpha = 0
                self?.focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            })
            
            
        }, completion: { [weak self] finished in
            if finished {
                self?.focusView.isHidden = true
            }
        })
    }
    
    
    public func focusCamera(toPoint: CGPoint) -> Bool {
        
        guard let device = camera, let preview = preview, device.isFocusModeSupported(.continuousAutoFocus) else {
            return false
        }
        
        do { try device.lockForConfiguration() } catch {
            return false
        }
        
        let focusPoint = preview.captureDevicePointConverted(fromLayerPoint: toPoint)
        
        device.focusPointOfInterest = focusPoint
        device.focusMode = .continuousAutoFocus
        
        device.exposurePointOfInterest = focusPoint
        device.exposureMode = .continuousAutoExposure
        
        device.unlockForConfiguration()
        
        return true
    }
    
    
    @objc internal func pinch(gesture: UIPinchGestureRecognizer) {
        guard let device = camera else { return }
        
        // Return zoom value between the minimum and maximum zoom values
        func minMaxZoom(_ factor: CGFloat) -> CGFloat {
            return min(max(factor, 1.0), device.activeFormat.videoMaxZoomFactor)
        }
        
        func update(scale factor: CGFloat) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = factor
            } catch {
                print("\(error.localizedDescription)")
            }
        }
        
        let velocity = gesture.velocity
        let velocityFactor: CGFloat = 8.0
        let desiredZoomFactor = device.videoZoomFactor + atan2(velocity, velocityFactor)
        
        let newScaleFactor = minMaxZoom(desiredZoomFactor)
        switch gesture.state {
        case .began, .changed:
            update(scale: newScaleFactor)
        case _:
            break
        }
    }
    
    
    public func cycleFlash() {
        guard let device = camera, device.hasFlash else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            if self.flash == .on {
                self.flash = .off
            } else if self.flash == .off {
                self.flash = .auto
            } else {
                self.flash = .on
            }
            device.unlockForConfiguration()
        } catch _ { }
    }
    
    
    public func swapCameraInput() {
        
        guard let session = session, let currentInput = input else {
            return
        }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        if currentInput.device.position == AVCaptureDevice.Position.back {
            currentPosition = AVCaptureDevice.Position.front
            
        } else {
            currentPosition = AVCaptureDevice.Position.back
        }
        
        camera = AVCaptureDevice.default(
            AVCaptureDevice.DeviceType.builtInWideAngleCamera,
            for: AVMediaType.video,
            position: currentPosition)
        
        guard let newInput = try? AVCaptureDeviceInput(device: camera) else {
            return
        }
        
        input = newInput
        
        session.addInput(newInput)
        session.commitConfiguration()
    }
}


extension CameraView : AVCapturePhotoCaptureDelegate{
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let imageData = photo.fileDataRepresentation()
        
        let photo = UIImage(data: imageData!)
        
        
        self.delegate?.photoOutput(photo)
        
        
    }
}
