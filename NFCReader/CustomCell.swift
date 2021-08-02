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
    @IBOutlet var returnButton: UIButton!
    @IBOutlet var loanButton: UIButton!
    @IBOutlet var clearButton: UIButton!
    
    @available(iOS 13.0, *)
    func startSession() {
        session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
        session?.alertMessage = "Hold your iPhone near the item."
        session?.begin()
    }
    
    @IBAction func selectReturnButton(_ sender: UIButton) {
        mode = "RETURN"
        startSession()
    }
    
    func getRootViewController() -> ViewController {
        return self.window?.rootViewController as! ViewController
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
                let securityMode: NFCSecurityMode = self.getRootViewController().nfcSecurityMode
                if securityMode == .AFI {
                    self.writeAfi(sTag)
                } else if securityMode == .EAS {
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
        let securityMode: NFCSecurityMode = getRootViewController().nfcSecurityMode
        var modeBytes: UInt8! = 0xC2
        if mode == "LOAN" {
            modeBytes = getLoanBytes(nfcSecurityMode: securityMode)
        } else if mode == "RETURN" {
            modeBytes = getReturnBytes(nfcSecurityMode: securityMode)
        } else if mode == "CLEAR" {
            modeBytes = 0x00
        }
        return modeBytes
    }
    
    @available(iOS 14.0, *)
    func writeEas(_ iso15693Tag: NFCISO15693Tag) {
        let modeByte: UInt8 = getByteByMode(mode: self.mode)
        print("modeBytes :: \(modeByte)")

        let writeEas = DispatchWorkItem {
//            print("0x00 :: \(0x00)") //0
//            print("0x01 :: \(0x01)") // 1
//            iso15693Tag.select(requestFlags: [.highDataRate], completionHandler: { (error) in
//                iso15693Tag.customCommand(requestFlags: [.highDataRate, .address], customCommandCode: 0xA2,
//                                          customRequestParameters: Data([0x01]),
//                                          resultHandler: { (result: Result<Data, Error>) in
//                                            switch result {
//                                                case .success(let data) :
//                                                    print("Data:: \(data)")
//                                                case .failure(let error):
//                                                    print("customCommandError :: \(error)")
//                                            }
//                                          })
//            })
            
            
            iso15693Tag.select(requestFlags: [.highDataRate, .address], completionHandler: {(error: Error?) in
                if error != nil {
                    print("SELECT ERROR :: \(error)")
                    self.session?.invalidate(errorMessage: "Error select!")
                    return
                }
//                let config: NFCISO15693CustomCommandConfiguration = NFCISO15693CustomCommandConfiguration.init(manufacturerCode: iso15693Tag.icManufacturerCode, customCommandCode: 0xA2, requestParameters: Data([0x01,0x01]), maximumRetries: 3, retryInterval: 2.0)
//                iso15693Tag.sendCustomCommand(commandConfiguration: config, completionHandler: { (data: Data, error: Error?) in
//                    if error != nil {
//                        print("Error!!! :: \(error)")
//                    }
//                    print("!@#!@#@! :: \(data)")
//                })
                iso15693Tag.sendRequest(requestFlags: 0x02, commandCode: 0xA2, data: Data([0x01]), resultHandler: { (result: Result<(NFCISO15693ResponseFlag, Data?), Error>) in
                    switch result {
                        case .success((let response, let data)):
                            print("sendRequest :: \(response)")
                            print(data)
                        case .failure(let error):
                            print("response :: \(error)")
                    }
                })
                
            })
        }
        
        let endSession = DispatchWorkItem {
            self.session?.alertMessage = "Complete Write NFC Data."
            self.session?.invalidate()
        }
        DispatchQueue.main.sync(execute: writeEas)
        DispatchQueue.global(qos: .userInteractive).async(execute: endSession)
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
        DispatchQueue.global().async(execute: endSession)
    }
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    
}
