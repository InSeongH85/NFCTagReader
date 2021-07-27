//
//  ViewController.swift
//  NFCReader
//
//  Created by InSeongHwang on 2021/07/16.
//

import UIKit
import CoreNFC

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, NFCTagReaderSessionDelegate{
  @IBOutlet var tableView: UITableView!
  // cell reuse id (cells that scroll out of view can be reused)
  let cellReuseIdentifier = "customCell"
  var session: NFCTagReaderSession?
  var barcodeSet = [String]()
  var barcode: String! = ""
  var currentStatus: String! = ""
  
  override func viewDidLoad() {
    super.viewDidLoad()
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
    self.session = nil
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
        self.showErrorByErroCode(readerError)
        session.invalidate()
        return
      } else if nil != error {
        self.showErrorByMessage("Error to Connect")
        session.invalidate()
        return
      }
      
      if case let .iso15693(sTag) = tags.first! {
        self.readDataInTag(sTag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
          self.tableView?.reloadData()
        })
      }
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
  @available(iOS 13.0, *)
  func readDataInTag(_ iso15693Tag: NFCISO15693Tag) {
    let setAfiStatus = DispatchWorkItem {
      var currentAfiStatus: Int!
      iso15693Tag.getSystemInfo(requestFlags: [.highDataRate], resultHandler: { (result: Result<NFCISO15693SystemInfo, Error>) in
        switch result {
          case .success(let sysInfo):
            currentAfiStatus = sysInfo.applicationFamilyIdentifier
            if currentAfiStatus == -1 {
              self.showErrorByMessage("Not set AFI Status.")
              self.session?.invalidate()
              return
            } else if currentAfiStatus == 0x07 {
              self.currentStatus = "대출가능"
            } else if currentAfiStatus == 0xC2 {
              self.currentStatus = "대출중"
            }
          case .failure(let error):
            self.showErrorByErroCode(error as! NFCReaderError)
            self.session?.invalidate()
        }
      })
    }
    
    let readTagWorkItem = DispatchWorkItem {
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
    
    let proccessDatas = DispatchWorkItem {
      let trimData: String = self.barcode.trimmingCharacters(in: .controlCharacters)
      if trimData.count > 0 {
        self.barcode = trimData + "::: " + self.currentStatus!
        self.barcodeSet.append(self.barcode)
        self.session?.alertMessage = "Complete read NFC Data."
        self.session?.invalidate()
      }
    }
    DispatchQueue.global().sync(execute: readTagWorkItem)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: setAfiStatus)
    DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: proccessDatas)
  }
}

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}
