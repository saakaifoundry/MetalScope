//
//  PanoramaView.swift
//  MetalScope
//
//  Created by Jun Tanaka on 2017/01/17.
//  Copyright © 2017 eje Inc. All rights reserved.
//

import UIKit
import SceneKit

public final class PanoramaViewRotationRange {
    public let max : Float
    public let min : Float
    public init(min: Float, max: Float) {
        self.max = max
        self.min = min
    }
}

public final class PanoramaView: UIView, SceneLoadable {
    #if (arch(arm) || arch(arm64)) && os(iOS)
    public let device: MTLDevice
    #endif
    
    public var scene: SCNScene? {
        get {
            return scnView.scene
        }
        set(value) {
            orientationNode.removeFromParentNode()
            value?.rootNode.addChildNode(orientationNode)
            scnView.scene = value
        }
    }

    public weak var sceneRendererDelegate: SCNSceneRendererDelegate?

    public lazy var orientationNode: OrientationNode = {
        let node = OrientationNode()
        let mask = CategoryBitMask.all.subtracting(.rightEye)
        node.pointOfView.camera?.categoryBitMask = mask.rawValue
        return node
    }()

    lazy var scnView: SCNView = {
        #if (arch(arm) || arch(arm64)) && os(iOS)
        let view = SCNView(frame: self.bounds, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
            SCNView.Option.preferredDevice.rawValue: self.device
        ])
        #else
        let view = SCNView(frame: self.bounds)
        #endif
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.delegate = self
        view.pointOfView = self.orientationNode.pointOfView
        view.isPlaying = true
        self.addSubview(view)
        return view
    }()

    fileprivate lazy var panGestureManager: PanoramaPanGestureManager = {
        let manager = PanoramaPanGestureManager(rotationNode: self.orientationNode.userRotationNode)
        return manager
    }()

    
    fileprivate lazy var interfaceOrientationUpdater: InterfaceOrientationUpdater = {
        return InterfaceOrientationUpdater(orientationNode: self.orientationNode)
    }()

    #if (arch(arm) || arch(arm64)) && os(iOS)
    @objc public init(frame: CGRect, device: MTLDevice) {
        self.device = device
        super.init(frame: frame)
        self.panGestureManager.minimumVerticalRotationAngle = -60 / 180 * .pi
        self.panGestureManager.maximumVerticalRotationAngle = 60 / 180 * .pi
        addGestureRecognizer(self.panGestureManager.gestureRecognizer)
    }
    
    #else
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.panGestureManager.minimumVerticalRotationAngle = -60 / 180 * .pi
        self.panGestureManager.maximumVerticalRotationAngle = 60 / 180 * .pi
        addGestureRecognizer(self.panGestureManager.gestureRecognizer)
    }
    #endif

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        orientationNode.removeFromParentNode()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        scnView.frame = bounds
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            interfaceOrientationUpdater.stopAutomaticInterfaceOrientationUpdates()
        } else {
            interfaceOrientationUpdater.startAutomaticInterfaceOrientationUpdates()
            interfaceOrientationUpdater.updateInterfaceOrientation()
        }
    }
}

extension PanoramaView: ImageLoadable {}

#if (arch(arm) || arch(arm64)) && os(iOS)
extension PanoramaView: VideoLoadable {}
#endif

extension PanoramaView {
    public var sceneRenderer: SCNSceneRenderer {
        return scnView
    }

    public var isPlaying: Bool {
        get {
            return scnView.isPlaying
        }
        set(value) {
            scnView.isPlaying = value
        }
    }

    public var antialiasingMode: SCNAntialiasingMode {
        get {
            return scnView.antialiasingMode
        }
        set(value) {
            scnView.antialiasingMode = value
        }
    }

    public func snapshot() -> UIImage {
        return scnView.snapshot()
    }

    public var panGestureRecognizer: UIPanGestureRecognizer {
        return panGestureManager.gestureRecognizer
    }

    public func updateInterfaceOrientation() {
        interfaceOrientationUpdater.updateInterfaceOrientation()
    }

    public func updateInterfaceOrientation(with transitionCoordinator: UIViewControllerTransitionCoordinator) {
        interfaceOrientationUpdater.updateInterfaceOrientation(with: transitionCoordinator)
    }

    public func setNeedsResetRotation(animated: Bool = false) {
        panGestureManager.stopAnimations()
        orientationNode.setNeedsResetRotation(animated: animated)
    }

    public func setNeedsResetRotation(_ sender: Any?) {
        setNeedsResetRotation(animated: true)
    }
}

extension PanoramaView {
    @objc public func setVerticalPanningEnabled(isEnabled: Bool = true) {
        panGestureManager.allowsVerticalRotation = isEnabled
    }
    
    @objc public func setDeviceOrientationTrackingEnabled(isEnabled: Bool = true) {
        if isEnabled {
            orientationNode.deviceOrientationProvider = DefaultDeviceOrientationProvider()
        } else {
            orientationNode.deviceOrientationProvider = nil
        }
    }
    
    @objc public func setHorizontalRotationAngles(minAngle: Float, maxAngle: Float) {
        panGestureManager.minimumHorizontalRotationAngle = minAngle / 360 * .pi
        panGestureManager.maximumHorizontalRotationAngle = maxAngle / 360 * .pi
    }
    
    @objc public func setFOV(fov: CGFloat) {
        orientationNode.fieldOfView = fov
    }
}

extension PanoramaView: OrientationIndicatorDataSource {
    public var pointOfView: SCNNode? {
        return orientationNode.pointOfView
    }

    public var viewportSize: CGSize {
        return scnView.bounds.size
    }
}

extension PanoramaView: SCNSceneRendererDelegate {
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        var disableActions = false

        if let provider = orientationNode.deviceOrientationProvider, provider.shouldWaitDeviceOrientation(atTime: time) {
            provider.waitDeviceOrientation(atTime: time)
            disableActions = true
        }

        SCNTransaction.lock()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1 / 15
        SCNTransaction.disableActions = disableActions

        orientationNode.updateDeviceOrientation(atTime: time)

        SCNTransaction.commit()
        SCNTransaction.unlock()

        sceneRendererDelegate?.renderer?(renderer, updateAtTime: time)
    }

    public func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        sceneRendererDelegate?.renderer?(renderer, didApplyAnimationsAtTime: time)
    }

    public func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        sceneRendererDelegate?.renderer?(renderer, didSimulatePhysicsAtTime: time)
    }

    public func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        sceneRendererDelegate?.renderer?(renderer, willRenderScene: scene, atTime: time)
    }

    public func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        sceneRendererDelegate?.renderer?(renderer, didRenderScene: scene, atTime: time)
    }
}
