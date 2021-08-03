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
    var nfcSecurityMode: NFCSecurityMode = .AFI
    @IBOutlet var customLabel: UILabel!
    @IBOutlet var returnButton: UIButton!
    @IBOutlet var loanButton: UIButton!
    @IBOutlet var clearButton: UIButton!
    
    @available(iOS 13.0, *)
    func startSession() {
        self.nfcSecurityMode = self.getRootViewController().nfcSecurityMode
        session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
        session?.alertMessage = "Hold your iPhone near the item."
        session?.begin()
    }
    
    func getRootViewController() -> ViewController {
        return UIApplication.shared.windows.first!.rootViewController as! ViewController
    }
    
    @IBAction func selectReturnButton(_ sender: UIButton) {
        mode = "RETURN"
        startSession()
    }
        
    @IBAction func selectLoanButton(_ sender: UIButton) {
        mode = "LOAN"
        startSession()
    }
    
    @IBAction func selectClearButton(_ sender: Any) {
        mode = "CLEAR"
        startSession()
    }
    
    @available(iOS 13.0, *)
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("tagReaderSessionDidBecomeActive!!! :: \(session)")
    }
    
    @available(iOS 13.0, *)
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
                if  self.nfcSecurityMode == .AFI {
                    self.writeAfi(sTag)
                } else if self.nfcSecurityMode == .EAS {
                    self.writeEas(sTag)
                } else {
                    session.invalidate(errorMessage: "Please Check NFC Security Mode.")
                }
                
            }
            session.alertMessage = "Complete Write NFC Data."
            session.invalidate()
        }
    }
    
    func getLoanBytes (nfcSecurityMode: NFCSecurityMode) -> UInt8 {
        var modeBytes: UInt8! = 0xC2
        if nfcSecurityMode == .AFI {
            modeBytes = 0xC2
        } else if nfcSecurityMode == .EAS {
            modeBytes = 0xA3
        }
        return modeBytes
    }
    
    func getReturnBytes (nfcSecurityMode: NFCSecurityMode) -> UInt8 {
        var modeBytes: UInt8! = 0x07
        if nfcSecurityMode == .AFI {
            modeBytes = 0x07
        } else if nfcSecurityMode == .EAS {
            modeBytes = 0xA2
        }
        return modeBytes
    }
    
    func getByteByMode (mode: String) -> UInt8 {
        var modeBytes: UInt8! = 0xC2
        if mode == "LOAN" {
            modeBytes = getLoanBytes(nfcSecurityMode:  self.nfcSecurityMode)
        } else if mode == "RETURN" {
            modeBytes = getReturnBytes(nfcSecurityMode:  self.nfcSecurityMode)
        } else if mode == "CLEAR" {
            modeBytes = 0x00
        }
        return modeBytes
    }
    
    // 타이밍....
    @available(iOS 14.0, *)
    func writeEas(_ iso15693Tag: NFCISO15693Tag) {
        let modeByte: UInt8 = getByteByMode(mode: self.mode)
        print("modeBytes :: \(modeByte.toHexString())")
        iso15693Tag.select(requestFlags: [.highDataRate], completionHandler: { (error) in
            if error != nil {
                self.session?.invalidate(errorMessage: error.debugDescription)
            }
            iso15693Tag.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA3,
                                      customRequestParameters: Data(),
                                      resultHandler: { (result: Result<Data, Error>) in
                                        switch result {
                                            case .success(let data) :
                                                print("Data:: \(data)")
                                                self.session?.invalidate()
                                            case .failure(let error):
                                                print("customCommandError :: \(error)")
                                                self.session?.invalidate(errorMessage: error.localizedDescription)
                                        }
                                      })
                
        })
        
//        iso15693Tag.select(requestFlags: [.highDataRate], completionHandler: { (error) in
//            if error != nil {
//                self.session?.invalidate(errorMessage: error.debugDescription)
//            }
//            iso15693Tag.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA3,
//                                      customRequestParameters: Data(),
//                                      resultHandler: { (result: Result<Data, Error>) in
//                                        switch result {
//                                            case .success(let data) :
//                                                print("Data:: \(data)")
//                                                self.session?.invalidate()
//                                            case .failure(let error):
//                                                print("customCommandError :: \(error)")
//                                                self.session?.invalidate(errorMessage: error.localizedDescription)
//                                        }
//                                      })
//        })
    

//        DispatchQueue.global().sync(execute: writeEas)
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: endSession)
    }
    
    
    
    // https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
    // 대출 / 반납 의 상태를 NFC 의 AFI 에 쓴다.
    // 대출 일 시 0xC2 :: out of stock
    // 반납 일 시 0x07 :: in stock
    // 대출상태 초기화 0x00
    @available(iOS 13.0, *)
    func writeAfi(_ iso15693Tag: NFCISO15693Tag) {
        let modeByte: UInt8 = getByteByMode(mode: self.mode)
        print("modeBytes :: \(modeByte)")
        let writeAFI = DispatchWorkItem {
            iso15693Tag.writeAFI(requestFlags: .highDataRate, afi: modeByte, completionHandler: { (error: Error?) in
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
        
        DispatchQueue.main.sync(execute: writeAFI)
        DispatchQueue.main.async(execute: endSession)
    }
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    
}
extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx ", $0) }.joined()
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
