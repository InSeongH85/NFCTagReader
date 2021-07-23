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
  let cellReuseIdentifier = "cell"
  var session: NFCTagReaderSession?
  var barcodeSet = [String]()
  var barcode: String! = ""
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Register the table view cell class and its reuse id
    self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
    // This view controller itself will provide the delegate methods and row data for the table view.
    tableView.delegate = self
    tableView.dataSource = self
  }
  
  @IBAction func _beginScanning(_ sender: Any) {
    guard NFCTagReaderSession.readingAvailable else {
        let alertController = UIAlertController(
            title: "Scanning Not Supported",
            message: "This device doesn't support tag scanning.",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
        return
    }
    session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
    session?.alertMessage = "Hold your iPhone near the item to learn more about it."
    session?.begin()
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    self.barcode = ""
  }
  
  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    print("tagReaderSession with Error :: \(error)")
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
    
    let firstTag = tags.first!
    
    session.connect(to: firstTag) { (error: Error?) in
      if error != nil {
        print("Error by Connect")
        session.invalidate(errorMessage: "Error by Connect")
        return
      }
      
      if case let .iso15693(sTag) = firstTag {
        self.readDataInTag(sTag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
          self.tableView.reloadData()
        })
      }
    }
  }
  
  /**
   https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
   */
  @available(iOS 13.0, *)
  func readDataInTag(_ iso15693Tag: NFCISO15693Tag) {
    
    let readTagWorkItem = DispatchWorkItem {
      let uInt8Arr: [UInt8] = [UInt8](0...79)
      for i in uInt8Arr {
        iso15693Tag.readSingleBlock(requestFlags: [.highDataRate], blockNumber: i) { (data: Data, error: Error?) in
          self.barcode.append(String(data: data, encoding: .ascii) ?? "")
        }
      }
    }
    
    let proccessDatas = DispatchWorkItem {
      let trimData: String = self.barcode.trimmingCharacters(in: .controlCharacters)
      if trimData.count > 0 {
        self.barcode = trimData
        self.barcodeSet.append(trimData)
        self.session?.alertMessage = "Complete read NFC Data."
        self.session?.invalidate()
      }
    }
    
    DispatchQueue.global().sync(execute: readTagWorkItem)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: proccessDatas)
  }
}

