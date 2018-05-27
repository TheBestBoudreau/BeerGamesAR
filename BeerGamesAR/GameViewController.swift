//
//  ViewController.swift
//  BeerGamesAR
//
//  Created by Brian Vo on 2018-05-25.
//  Copyright © 2018 Brian Vo & Ray Lin & Ramen Singh & Tyler Boudreau. All rights reserved.
//

import UIKit
import ARKit
import Firebase
import ARCore
import ModelIO
import SceneKit

enum ARState {
    case Default,
    CreatingRoom,
    RoomCreated,
    Hosting,
    HostingFinished,
    EnterRoomCode,
    Resolving,
    ResolvingFinished
};


class GameViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, GARSessionDelegate {
    
    // OUTLETS
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var hostButton: UIButton!
    @IBOutlet weak var resolveButton: UIButton!
    @IBOutlet weak var roomCodeLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    
    // API VARIABLES
    var firebaseReference: DatabaseReference?
    var gSession: GARSession?
    var arAnchor: ARAnchor?
    var garAnchor: GARAnchor?
    
    // ENUM VARIABLES
    var state: ARState?
    
    // NORMAL VARIABLES
    var message: String?
    var roomCode: String?
    
    // MARK - Overriding UIViewController
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        firebaseReference = Database.database().reference()
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        do {
            gSession = try GARSession.init(apiKey: ARCoreAPIKey, bundleIdentifier: nil)
        } catch {
            print("Couldn't initialize GAR session")
        }
        if let gSession = gSession {
            gSession.delegate = self
            gSession.delegateQueue = DispatchQueue.main
            enterState(state: .Default)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = .horizontal
        
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count < 1 || state != ARState.RoomCreated {
            return
        }
        let touch = touches.first!
        let touchLocation = touch.location(in: sceneView)
        
        let hitTestResult = sceneView.hitTest(touchLocation, types: [.existingPlane, .existingPlaneUsingExtent, .estimatedHorizontalPlane])
        if hitTestResult.count > 0 {
            guard let result = hitTestResult.first else { return }
            self.addAnchorWithTransform(transform: result.worldTransform)
        }
    }
    
    // MARK: Anchor Hosting / Resolving
    
    func resolveAnchorWithRoomCode(roomCode: String) {
        self.roomCode = roomCode
        enterState(state: .Resolving)
        weak var weakSelf = self
        firebaseReference?.child("hotspot_list").child(roomCode)
            .observe(.value, with: { (snapshot) in
                DispatchQueue.main.async {
                    let strongSelf = weakSelf
                    if strongSelf == nil || strongSelf?.state != ARState.Resolving ||
                        !(strongSelf?.roomCode == roomCode) {
                        return
                    }
                    var anchorId: String?
                    if let value = snapshot.value as? NSDictionary {
                        anchorId = value["hosted_anchor_id"] as? String
                    }
                    if let anchorId = anchorId, let strongSelf = strongSelf {
                        strongSelf.firebaseReference?.child("hotspot_list").child(roomCode).removeAllObservers()
                        strongSelf.resolveAnchorWithIdentifier(identifier: anchorId)
                    }
                }
            })
    }
    
    func resolveAnchorWithIdentifier(identifier: String) {
        // Now that we have the anchor ID from firebase, we resolve the anchor.
        // Success and failure of this call is handled by the delegate methods
        // session:didResolveAnchor and session:didFailToResolveAnchor appropriately.
        guard let gSession = gSession else { return }
        do {
            self.garAnchor = try gSession.resolveCloudAnchor(withIdentifier: identifier)
        } catch {
            print("Couldn't resolve cloud anchor")
        }
    }
    
    func addAnchorWithTransform(transform: matrix_float4x4) {
        arAnchor = ARAnchor.init(transform: transform)
        sceneView.session.add(anchor: arAnchor!)
        
        // To share an anchor, we call host anchor here on the ARCore session.
        // session:disHostAnchor: session:didFailToHostAnchor: will get called appropriately.
        do {
            garAnchor = try gSession?.hostCloudAnchor(arAnchor!)
            enterState(state: .Hosting)
        } catch {
            print("Error while trying to add new anchor")
        }
    }
    
    // MARK: Actions
    
    @IBAction func hostButtonPressed(_ sender: UIButton) {
        if state == ARState.Default {
            enterState(state: .CreatingRoom)
            createRoom()
        } else {
            enterState(state: .Default)
        }
    }
    
    @IBAction func resolveButtonPressed(_ sender: UIButton) {
        if state == ARState.Default {
            enterState(state: .EnterRoomCode)
        } else {
            enterState(state: .Default)
        }
    }
    
    
    // MARK: Helper Methods
    
    func updateMessageLabel() {
        self.messageLabel.text = self.message
        self.roomCodeLabel.text = "Room: \(roomCode ?? "0000")"
    }
    
    func toggleButton(button: UIButton?, enabled: Bool, title: String?) {
        guard let button = button, let title = title else { return }
        button.isEnabled = enabled
        button.setTitle(title, for: UIControlState.normal)
    }
    
    func cloudStateString(cloudState: GARCloudAnchorState) -> String {
        switch (cloudState) {
        case .none:
            return "None";
        case .success:
            return "Success";
        case .errorInternal:
            return "ErrorInternal";
        case .taskInProgress:
            return "TaskInProgress";
        case .errorNotAuthorized:
            return "ErrorNotAuthorized";
        case .errorResourceExhausted:
            return "ErrorResourceExhausted";
        case .errorServiceUnavailable:
            return "ErrorServiceUnavailable";
        case .errorHostingDatasetProcessingFailed:
            return "ErrorHostingDatasetProcessingFailed";
        case .errorCloudIdNotFound:
            return "ErrorCloudIdNotFound";
        case .errorResolvingSdkVersionTooNew:
            return "ErrorResolvingSdkVersionTooNew";
        case .errorResolvingSdkVersionTooOld:
            return "ErrorResolvingSdkVersionTooOld";
        case .errorResolvingLocalizationNoMatch:
            return "ErrorResolvingLocalizationNoMatch";
        }
    }
    
    func showRoomCodeDialog() {
        let alertController = UIAlertController(title: "ENTER ROOM CODE", message: "", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            guard let alertControllerTextFields = alertController.textFields else { return }
            guard let roomCode = alertControllerTextFields[0].text else { return }
            if roomCode.count == 0 {
                self.enterState(state: .Default)
            } else {
                self.resolveAnchorWithRoomCode(roomCode: roomCode)
            }
        }
        let cancelAction = UIAlertAction(title: "CANCEL", style: .default) { (action) in
            self.enterState(state: .Default)
        }
        alertController.addTextField { (textField) in
            textField.keyboardType = UIKeyboardType.numberPad
        }
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: false, completion: nil)
        
    }
    
    func enterState(state: ARState) {
        switch (state) {
        case .Default:
            if let arAnchor = arAnchor {
                sceneView.session.remove(anchor: arAnchor)
                self.arAnchor = nil;
            }
            if let gSession = gSession, let garAnchor = garAnchor {
                gSession.remove(garAnchor)
                self.garAnchor = nil;
            }
            if (self.state == .CreatingRoom) {
                self.message = "Failed to create room. Tap HOST or RESOLVE to begin.";
            } else {
                self.message = "Tap HOST or RESOLVE to begin.";
            }
            if (self.state == .EnterRoomCode) {
                self.dismiss(animated: false, completion: nil)
            } else if (self.state == .Resolving) {
                if let firebaseReference = firebaseReference, let roomCode = roomCode {
                    firebaseReference.child("hotspot_list").child(roomCode).removeAllObservers()
                }
            }
            toggleButton(button: hostButton, enabled: true, title: "HOST")
            toggleButton(button: resolveButton, enabled: true, title: "RESOLVE")
            roomCode = "";
            break;
        case .CreatingRoom:
            self.message = "Creating room...";
            toggleButton(button: hostButton, enabled: false, title: "HOST")
            toggleButton(button: resolveButton, enabled: false, title: "RESOLVE")
            break;
        case .RoomCreated:
            self.message = "Tap on a plane to create anchor and host.";
            toggleButton(button: hostButton, enabled: true, title: "CANCEL")
            toggleButton(button: resolveButton, enabled: false, title: "RESOLVE")
            break;
        case .Hosting:
            self.message = "Hosting anchor...";
            break;
        case .HostingFinished:
            guard let garAnchor = self.garAnchor else { return }
            self.message = "Finished hosting: \(garAnchor.cloudState)"
            break;
        case .EnterRoomCode:
            self.showRoomCodeDialog()
            break;
        case .Resolving:
            self.dismiss(animated: false, completion: nil)
            self.message = "Resolving anchor...";
            toggleButton(button: hostButton, enabled: false, title: "HOST")
            toggleButton(button: resolveButton, enabled: true, title: "CANCEL")
            break;
        case .ResolvingFinished:
            guard let garAnchor = self.garAnchor else { return }
            self.message = "Finished resolving \(self.cloudStateString(cloudState: garAnchor.cloudState))"
            break;
        }
        self.state = state;
        self.updateMessageLabel()
    }
    
    func createRoom() {
        weak var weakSelf = self
        var roomNumber = 0
        firebaseReference?.child("last_room_code").runTransactionBlock({ (currentData) -> TransactionResult in
            let strongSelf = weakSelf
            
            // cast last room number from firebase database to variable "lastRoomNumber", if unwrapping fails, set lastRoomNumber to 0, which mean there is no last room number documented in firebase database
            if let lastRoomNumber = currentData.value as? Int{
                roomNumber = lastRoomNumber
            } else {
                roomNumber = 0
            }
            
            // Increment the room number and set it as new room number
            roomNumber += 1
            let newRoomNumber = NSNumber(value: roomNumber)
            
            // create timestamp for the room number
            let currentTimestamp = Date()
            let timestampeInt = Int(currentTimestamp.timeIntervalSince1970 * 1000)
            let timestamp = NSNumber(value: timestampeInt)
            
            // pass room number as string and timestamp into newRoom dictionary
            let newRoom = ["display_name" : newRoomNumber.stringValue,
                           "updated_at_timestamp" : timestamp] as [String : Any]
            
            // create a new node in firebase under hotspot_list to document the new room info with newRoom variable
            strongSelf?.firebaseReference?.child("hotspot_list").child(newRoomNumber.stringValue).setValue(newRoom)
            
            // update node "last_rooom_code" as reference for next room creation
            currentData.value = newRoomNumber
            return TransactionResult.success(withValue: currentData)
            
        },andCompletionBlock: { (error, committed, snapshot) in
            DispatchQueue.main.async {
                if error != nil{
                    weakSelf?.enterState(state: .Default)
                }else {
                    if let roomNumber = snapshot?.value as? NSNumber{
                        weakSelf?.roomCreated(roomCode: roomNumber.stringValue)
                    }
                }
            }
        })
    }
    
    private func roomCreated(roomCode: String){
        self.roomCode = roomCode
        self.enterState(state: .RoomCreated)
    }
    
    // Mark - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // render SCN object
        if !(anchor.isMember(of: ARPlaneAnchor.self)) {
            let scene = SCNScene(named: "example.scnassets/andy.scn")
            return scene?.rootNode.childNode(withName: "andy", recursively: false)
        }
        let scnNode = SCNNode()
        return scnNode
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // determine position and size of the plane anchor
        if anchor.isMember(of: ARPlaneAnchor.self) {
            let planeAnchor = anchor as? ARPlaneAnchor
            
            guard let width = planeAnchor?.extent.x, let height = planeAnchor?.extent.z else {
                return
            }
            let plane = SCNPlane.init(width: CGFloat(width), height: CGFloat(height))
            
            plane.materials.first?.diffuse.contents = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.3)
            
            let planeNode = SCNNode(geometry: plane)
            
            if let x = planeAnchor?.center.x, let y = planeAnchor?.center.y, let z = planeAnchor?.center.z {
                planeNode.position = SCNVector3Make(x, y, z)
                planeNode.eulerAngles = SCNVector3Make(Float(-Double.pi / 2), 0, 0)
            }
            
            node.addChildNode(planeNode)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update position and size of plane anchor
        if anchor.isMember(of: ARPlaneAnchor.self){
            let planeAnchor = anchor as? ARPlaneAnchor
            
            let planeNode = node.childNodes.first
            guard let plane = planeNode?.geometry as? SCNPlane else {return}
            
            if let width = planeAnchor?.extent.x {
                plane.width = CGFloat(width)
            }
            if let height = planeAnchor?.extent.z {
                plane.height = CGFloat(height)
            }
            
            if let x = planeAnchor?.center.x, let y = planeAnchor?.center.y, let z = planeAnchor?.center.z {
                planeNode?.position = SCNVector3Make(x, y, z)
            }
            
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // remove plane node from parent node
        if anchor.isMember(of: ARPlaneAnchor.self){
            let planeNode = node.childNodes.first
            planeNode?.removeFromParentNode()
        }
    }
    
}

