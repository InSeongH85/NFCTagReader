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
    var barcode: String! = ""
    var currentStatus: String! = ""
    
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
                self.readDataInTag(sTag)
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
    /**
     현재 AFI 상태를 가져온다.
     0x07 - 7 :: 대출가능 ( in stock)
     0XC2 - 194 :: 대출 중 (out of loan)
     
     func getCurrentAfiStatus(_ iso15693Tag: NFCISO15693Tag) {
     iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
     switch result {
     case .success(let sysInfo):
     self.currentAfiStatus = sysInfo.applicationFamilyIdentifier
     case .failure(let error):
     self.showErrorByErroCode(error as! NFCReaderError)
     self.session?.invalidate()
     }
     })
     }   */
    
    /**
     https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
     특정 block 만 읽기에는 등록번호가 고정적이지 않다.
     */
    @available(iOS 14.0, *)
    func readDataInTag(_ iso15693Tag: NFCISO15693Tag) {
        
        let readTagWorkItem = DispatchWorkItem {
            // bytes 가 모자란 경우에는 block 이 없기때문에 오류 발생됨. tag response error.
            let uInt8Arr: [UInt8] = [UInt8](0...79)
            for i in uInt8Arr {
                iso15693Tag.readSingleBlock(requestFlags: [.highDataRate], blockNumber: i, resultHandler: { (result: Result<Data, Error>) in
                    switch result {
                        case .success(let data):
                            self.barcode.append(String(data: data, encoding: .ascii) ?? "")
                        case .failure(let error):
                            self.showErrorByErroCode(error as! NFCReaderError)
                    }
                })
            }
        }
        
        let setAfiStatus = DispatchWorkItem {
            var currentAfiStatus: Int!
            iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
                switch result {
                    case .success(let sysInfo):
                        currentAfiStatus = sysInfo.applicationFamilyIdentifier
                        if currentAfiStatus == 0x07 {
                            self.currentStatus = "대출가능"
                        } else if currentAfiStatus == 0xC2 {
                            self.currentStatus = "대출중"
                        } else {
                            self.currentStatus = ""
                        }
                    case .failure(let error):
                        self.session?.invalidate(errorMessage: (error as! NFCReaderError).localizedDescription)
                }
            })
        }
        
        let proccessDatas = DispatchWorkItem {
            let tmpBarcode: [Substring] = self.barcode.split(separator: "\0")
            let trimData: String = self.barcode.trimmingCharacters(in: .controlCharacters)
            if tmpBarcode.count <= 1 {
                self.session?.invalidate(errorMessage: "barcode error")
            } else {
                self.barcode = "\(trimData) ::: \(self.currentStatus!)"
                self.barcode = tmpBarcode[1].trimmingCharacters(in: .controlCharacters)  + "::: \(self.currentStatus!)"
                self.barcodeSet.append(self.barcode)
                self.session?.alertMessage = "Complete read NFC Data."
                self.session?.invalidate()
            }
        }
        DispatchQueue.global().sync(execute: readTagWorkItem)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1, execute: setAfiStatus)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2, execute: proccessDatas)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
            self.tableView?.reloadData()
        })
    }
}

