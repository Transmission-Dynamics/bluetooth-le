//
//  FirmwareUpdater.swift
//  Plugin
//
//  Created by Miłosz Dubiel on 04/09/2023.
//

import Foundation
import CoreBluetooth
import iOSDFULibrary

class FirmwareUpdater: DFUServiceDelegate, LoggerDelegate, DFUProgressDelegate {
    typealias NotifyCallback = (_ key: String, _ message: [String: Any]) -> Void
    typealias Callback = (_ success: Bool, _ message: String) -> Void

    private let dfuInitiator: DFUServiceInitiator

    private let fileUrl: URL
    private let peripheral: CBPeripheral

    private let notifyCallback: NotifyCallback
    private let notifyKey: String

    private let callback: Callback
    private let callbackKey: String

    private var firmware: DFUFirmware?
    private var controller: DFUServiceController? = nil

    init(
        fileUrl: URL,
        peripheral: CBPeripheral,
        notifyCallback: NotifyCallback?,
        callback: @escaping Callback,
        dfuInitiator: DFUServiceInitiator,
        setUniqueDeviceNameInDfuMode: Bool
    ) {
        self.fileUrl = fileUrl
        self.peripheral = peripheral

        self.notifyCallback = notifyCallback!
        self.notifyKey = "updateDFUNotification|\(peripheral.identifier.uuidString)"

        self.callback = callback
        self.callbackKey = "updateDFU|\(peripheral.identifier.uuidString)"

        self.dfuInitiator = dfuInitiator
        self.dfuInitiator.alternativeAdvertisingNameEnabled = setUniqueDeviceNameInDfuMode
        self.dfuInitiator.delegate = self
        self.dfuInitiator.progressDelegate = self
        self.dfuInitiator.logger = self
    }

    private func prepareFirmware() {
        self.firmware = try! DFUFirmware(urlToZipFile: self.fileUrl)
    }

    func start() {
        self.prepareFirmware()

        self.controller = self.dfuInitiator
            .with(firmware: self.firmware!)
            .start(target: self.peripheral)
    }

    func cancel() -> Bool {
        guard let controller = self.controller else { return true }
        return controller.abort()
    }
    
    func dfuStateDidChange(to state: DFUState) {
        var stateStr: String = "unknown";
        switch(state) {
        case DFUState.connecting: stateStr = "deviceConnecting"; break;
        case DFUState.starting: stateStr = "dfuProcessStarting"; break;
        case DFUState.enablingDfuMode: stateStr = "enablingDfuMode"; break;
        case DFUState.uploading: stateStr = "firmwareUploading"; break;
        case DFUState.validating: stateStr = "firmwareValidating"; break;
        case DFUState.disconnecting: stateStr = "deviceDisconnecting"; break;
        case DFUState.completed: stateStr = "dfuCompleted"; break;
        case DFUState.aborted: stateStr = "dfuCancelled"; break;
        }

        self.notifyCallback(self.notifyKey, ["status": stateStr])

        if (state == DFUState.aborted) {
            self.callback(false, "Device firmware update cancelled")
        }
        if (state == DFUState.completed) {
            self.callback(true, "Device firmware update completed")
        }
    }
    
    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        self.callback(false, message)
    }
    
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        let message = [
            "status": "progressChanged",
            "progress": [
                "percent": progress,
                "speed": currentSpeedBytesPerSecond,
                "avgSpeed": avgSpeedBytesPerSecond,
                "currentPart": part,
                "partsTotal": totalParts,
            ] as [String : Any]
        ] as [String : Any]

        self.notifyCallback(self.notifyKey, message)
    }

    // LoggerDelegate (begin)
    func logWith(_ level: LogLevel, message: String) {
        print("DFU log message (\(level.name())): \(message)")
    }
    // LoggerDelegate (end)}
}
