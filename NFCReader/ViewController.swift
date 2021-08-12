//
//  ViewController.swift
//  NFCReader
//
//  Created by InSeongHwang on 2021/07/16.
//

import UIKit
import CoreNFC

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, NFCTagReaderSessionDelegate {
    @IBOutlet var segmentedControl: UISegmentedControl!
    @IBOutlet var tableView: UITableView!
    var nfcSecurityMode: NFCSecurityMode = .AFI
    let cellReuseIdentifier = "customCell"
    var session: NFCTagReaderSession?
    var barcodeSet = [String]()
    var barcode: String = ""
    var currentStatus: String! = ""
    var semaphoreCount: Int = 0
    var totalBlocks: Int = 0
    var nfcReadMode: String = try! Configuration.value(for: "NFC_READ_MODE")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        segmentedControl.selectedSegmentIndex = 0
    }
    
    @IBAction func selectedMode(_ sender: UISegmentedControl) {
        switch segmentedControl.selectedSegmentIndex {
            case 0:
                nfcSecurityMode = .AFI
            case 1:
                nfcSecurityMode = .EAS
            default:
                nfcSecurityMode = .AFI
        }
    }
    
    @available(iOS 14.0, *)
    func showErrorByErroCode(_ readerError: NFCReaderError) {
        if readerError.code != .readerSessionInvalidationErrorUserCanceled {
            let alertController = UIAlertController(
                title: "NFC Tag Not Connected.",
                message: readerError.localizedDescription,
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    @available(iOS 13.0, *)
    func showErrorByMessage(_ errorMessage: String) {
        let alertController = UIAlertController(
            title: "Session Invalidated",
            message: errorMessage,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    @available(iOS 13.0, *)
    @IBAction func _beginScanning(_ sender: UIButton) {
        guard NFCTagReaderSession.readingAvailable else {
            showErrorByMessage("This device doesn't support tag scanning.")
            return
        }
        guard nfcReadMode != "" else {
            self.session?.invalidate(errorMessage: "Checked read mode.")
            return
        }
        
        session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
        session?.alertMessage = "Hold your iPhone near the item."
        session?.begin()
    }
    
    @available(iOS 13.0, *)
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        self.barcode = ""
    }
    
    @available(iOS 13.0, *)
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            showErrorByErroCode(readerError)
        }
    }
    
    @available(iOS 13.0, *)
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than 1 tag is detected, please remove all tags and try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
                session.restartPolling()
            })
            return
        }
        
        session.connect(to: tags.first!) { (error: Error?) in
            if let readerError = error as? NFCReaderError {
                session.invalidate(errorMessage: readerError.localizedDescription)
                return
            } else if nil != error {
                session.invalidate(errorMessage: "Error to Connect")
                return
            }
            if case let .iso15693(sTag) = tags.first! {
                if self.nfcReadMode == "BARCODE" {
                    self.readBarcodeInTag(sTag)
                } else if self.nfcReadMode == "SERIAL" {
                    self.readSerialInTag(sTag)
                }
                
            }
        }
    }
    
    func tagRemovalDetect(_ tag: NFCTag) {
           self.session?.connect(to: tag) { (error: Error?) in
               if error != nil || !tag.isAvailable {
                   self.session?.restartPolling()
                   return
               }
               DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500), execute: {
                   self.tagRemovalDetect(tag)
               })
           }
       }
    
    
    @available(iOS 14.0, *)
    func readSerialInTag(_ iso15693Tag: NFCISO15693Tag) {
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: self.semaphoreCount)
            self.getSerialNo(iso15693Tag, semaphore)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.tableView?.reloadData()
        })
    }
    
    // https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
    // 특정 block 만 읽기에는 등록번호가 고정적이지 않다.
    @available(iOS 14.0, *)
    func readBarcodeInTag(_ iso15693Tag: NFCISO15693Tag) {
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: self.semaphoreCount)
            self.setTotalBlocks(iso15693Tag, semaphore)
            self.setBarcodeByTagData(iso15693Tag, semaphore)
            self.setCurrentStatus(iso15693Tag, semaphore)
            self.proccessDatas(semaphore)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.tableView?.reloadData()
        })
    }
    
    func setTotalBlocks(_ iso15693Tag: NFCISO15693Tag, _ semaphore: DispatchSemaphore) {
        semaphore.wait()
        iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
            switch result {
                case .success(let info):
                    print(info.totalBlocks)
                    self.totalBlocks = info.totalBlocks
                    semaphore.signal()
                case .failure(let error):
                    self.showErrorByErroCode(error as! NFCReaderError)
            }
        })
    }
    
    // NFC_READ_MODE 가 SERIAL 이라면 진행
    func getSerialNo(_ iso15693Tag: NFCISO15693Tag, _ semaphore: DispatchSemaphore) {
        semaphore.wait()
        iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
            switch result {
                case .success(let info):
                    let uuidData: Data = Data([UInt8](info.uniqueIdentifier).reversed())
                    self.barcode = uuidData.toHexString().removingWhitespaces()
                    self.barcodeSet.append(self.barcode)
                    self.session?.alertMessage = "Complete read NFC Data."
                    self.session?.invalidate()
                    semaphore.signal()
                case .failure(let error):
                    self.showErrorByErroCode(error as! NFCReaderError)
            }
        })
    }
    
    // NFC_READ_MODE 가 BARCODE 라면 진행
    func setBarcodeByTagData(_ iso15693Tag: NFCISO15693Tag, _ semaphore: DispatchSemaphore) {
        // bytes 가 모자란 경우에는 block 이 없기때문에 오류 발생됨. tag response error.
        // TODO: SLIX 하위 : 28 , SLIX2: 80
        semaphore.wait()
        let tmpSeq = UInt8.init(self.totalBlocks - 1)
        let readBlocks: [UInt8] = [UInt8](0...tmpSeq)
        for i in readBlocks {
            iso15693Tag.readSingleBlock(requestFlags: [.highDataRate], blockNumber: i, resultHandler: { (result: Result<Data, Error>) in
                switch result {
                    case .success(let data):
                        self.barcode.append(String(data: data, encoding: .ascii) ?? "")
                    case .failure(let error):
                        self.showErrorByErroCode(error as! NFCReaderError)
                }
            })
        }
        semaphore.signal()
    }
    
    func setCurrentStatus(_ iso15693Tag: NFCISO15693Tag, _ semaphore: DispatchSemaphore) {
        var currentAfiStatus: Int!
        semaphore.wait()
        iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
            switch result {
                case .success(let sysInfo):
                    currentAfiStatus = sysInfo.applicationFamilyIdentifier
                    if currentAfiStatus == 0x07 {
                        self.currentStatus = "대출가능"
                    } else if currentAfiStatus == 0xC2 {
                        self.currentStatus = "대출중"
                    } else {
                        self.currentStatus = "상태없음"
                    }
                case .failure(let error):
                    self.session?.invalidate(errorMessage: (error as! NFCReaderError).localizedDescription)
            }
            semaphore.signal()
        })
    }
    
    // ControlCharacters 를 trim 시킨다.
    func trimmingControlCharacters(_ splitBarcode: Substring) -> String {
        return splitBarcode.trimmingCharacters(in: .controlCharacters)
    }
    
    func proccessDatas(_ semaphore: DispatchSemaphore) {
        semaphore.wait()
        let tmpBarcode: [Substring] = self.barcode.split(separator: "\0")
        if tmpBarcode.count <= 0 {
            self.session?.invalidate(errorMessage: "barcode error")
        } else {
            self.barcode = tmpBarcode.count == 1 ? trimmingControlCharacters(tmpBarcode[0]) : trimmingControlCharacters(tmpBarcode[1])
            self.barcode = "\(self.barcode) ::: \(self.currentStatus!)"
            self.barcodeSet.append(self.barcode)
            self.session?.alertMessage = "Complete read NFC Data."
            self.session?.invalidate()
        }
        semaphore.signal()
    }
}
extension String {
    func removingWhitespaces() -> String {
        return components(separatedBy: .whitespaces).joined()
    }
}

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhX ", $0) }.joined()
    }
}

extension Int {
    func toHexString() -> String {
        return String(format:"%02hhx", self)
    }
}

extension UInt8 {
    func toHexString() -> String {
        return String(format:"%02hhX", self)
    }
}
