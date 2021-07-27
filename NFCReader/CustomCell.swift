//
//  CustomCell.swift
//  NFCReader
//
//  Created by InSeongHwang on 2021/07/26.
//

import UIKit
import CoreNFC

class CustomCell: UITableViewCell, NFCTagReaderSessionDelegate {
  var mode: String! = "LOAN"
  var session: NFCTagReaderSession?
  @IBOutlet var customLabel: UILabel!
  @IBOutlet var stateLabel: UILabel!
  @IBOutlet var returnButton: UIButton!
  @IBOutlet var loanButton: UIButton!

  
  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    print("tagReaderSessionDidBecomeActive!!! :: \(session)")
  }
  
  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    print("tagReaderSession With Error !!! :: \(error)")
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
      if error != nil {
        print("Error by Connect")
        session.invalidate(errorMessage: "Error by Connect")
        return
      }
      
      if case let .iso15693(sTag) = tags.first! {
        DispatchQueue.main.sync {
          self.writeAfi(sTag)
        }
      }
      session.alertMessage = "Complete Write NFC Data."
      session.invalidate()
    }
  }
  
  /**
   https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
   대출 / 반납 의 상태를 NFC 의 AFI 에 쓴다.
  대출 일 시 0xC2 :: out of stock
  반납 일 시 0x07 :: in stock
   */
  @available(iOS 13.0, *)
  func writeAfi(_ iso15693Tag: NFCISO15693Tag) {
    print("self.mode :: \(self.mode!)")
    let modeBytes: UInt8 = self.mode == "LOAN" ? 0xC2 : 0x07
    let writeAFI = DispatchWorkItem {
      iso15693Tag.writeAFI(requestFlags: .highDataRate, afi: modeBytes, completionHandler: { (error: Error?) in
        if error != nil {
          self.session?.invalidate(errorMessage: "Error writeAfi")
          return
        }
      })
    }
    
    let endSession = DispatchWorkItem {
      self.session?.alertMessage = "Complete Write NFC Data."
      self.session?.invalidate()
    }
    
    DispatchQueue.global(qos: .userInteractive).sync(execute: writeAFI)
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: endSession)
  }
  override func awakeFromNib() {
    super.awakeFromNib()
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
  }

  func startSession() {
    session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
    session?.alertMessage = "Hold your iPhone near the item to learn more about it."
    session?.begin()
  }
  
  @IBAction func selectReturnButton(_ sender: UIButton) {
    mode = "RETURN"
    startSession()
  }
  
  @IBAction func selectLoanButton(_ sender: UIButton) {
    mode = "LOAN"
    startSession()
  }
  
}
