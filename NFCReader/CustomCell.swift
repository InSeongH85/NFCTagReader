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
    var rootView: ViewController?
    @IBOutlet var customLabel: UILabel!
    @IBOutlet var returnButton: UIButton!
    @IBOutlet var loanButton: UIButton!
    @IBOutlet var clearButton: UIButton!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.getRootViewController()
    }
    
    func getRootViewController() -> ViewController? {
        DispatchQueue.main.async {
            self.rootView = (UIApplication.shared.windows.first!.rootViewController as! ViewController)
        }
        return rootView ?? nil
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    @available(iOS 13.0, *)
    func startSession() {
        if self.rootView != nil {
            self.nfcSecurityMode = self.getRootViewController()!.nfcSecurityMode
            print(self.nfcSecurityMode)
            self.session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self)
            self.session?.alertMessage = "Hold your iPhone near the item."
            self.session?.begin()
        }
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
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {    }
    
    @available(iOS 13.0, *)
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            getRootViewController()?.showErrorByErroCode(readerError)
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
            if error != nil {
                print("Error by Connect")
                session.invalidate(errorMessage: "Error by Connect")
                return
            }
            
            if case let .iso15693(sTag) = tags.first! {
                if self.nfcSecurityMode == .AFI {
                    self.writeAfi(sTag)
                } else if self.nfcSecurityMode == .EAS {
                    self.writeEas(sTag)
                } else {
                    session.invalidate(errorMessage: "Please Check NFC Security Mode.")
                }
            }
        }
    }
    
    // self.nfcSecurityMode 에 따라서 대출할 시 Flag 를 가져온다.
    // AFI : 0xC2 out of loan
    // EAS : 0xA2 보안 해제
    func getLoanBytes () -> UInt8 {
        var modeBytes: UInt8! = 0xC2
        if self.nfcSecurityMode == .AFI {
            modeBytes = 0xC2
        } else if self.nfcSecurityMode == .EAS {
            modeBytes = 0xA3
        }
        return modeBytes
    }
    
    // self.nfcSecurityMode 에 따라서 반납할 시 Flag 를 가져온다.
    // AFI : 0x07 in stock
    // EAS : 0xA2 보안 설정
    func getReturnBytes () -> UInt8 {
        var modeBytes: UInt8! = 0x07
        if self.nfcSecurityMode == .AFI {
            modeBytes = 0x07
        } else if self.nfcSecurityMode == .EAS {
            modeBytes = 0xA2
        }
        return modeBytes
    }
    
    func getByteByMode (mode: String) -> UInt8 {
        var modeBytes: UInt8! = 0xC2
        if mode == "LOAN" {
            modeBytes = getLoanBytes()
        } else if mode == "RETURN" {
            modeBytes = getReturnBytes()
        } else if mode == "CLEAR" {
            modeBytes = 0x00
        }
        return modeBytes
    }
    
    // 대출 / 반납 의 상태를 NFC 의 EAS 에 쓴다.
    // 대출 일 시 0xA3 :: 보안 해제
    // 반납 일 시 0xA2 :: 보안 설정
    @available(iOS 14.0, *)
    func writeEas(_ iso15693Tag: NFCISO15693Tag) {
        let modeByte: UInt8 = getByteByMode(mode: self.mode)
        iso15693Tag.select(requestFlags: [.highDataRate], completionHandler: { (error: Error?) in
            if error != nil {
                self.session?.invalidate(errorMessage: error.debugDescription)
            }
            iso15693Tag.customCommand(requestFlags: [.highDataRate], customCommandCode: Int(modeByte),
                                      customRequestParameters: Data(),
                                      resultHandler: { (result: Result<Data, Error>) in
                                        switch result {
                                            case .success(_) :
                                                self.session?.alertMessage = "Change \(self.nfcSecurityMode) Flag Success. \(modeByte.toHexString())"
                                                self.session?.invalidate()
                                            case .failure(let error):
                                                print("customCommandError :: \(error)")
                                                self.session?.invalidate(errorMessage: error.localizedDescription)
                                        }
                                      })

        })
    }
    
    
    
    // https://www.nxp.com/docs/en/data-sheet/SL2S2602.pdf 9.2 Memory organization
    // 대출 / 반납 의 상태를 NFC 의 AFI 에 쓴다.
    // 대출 일 시 0xC2 :: out of stock
    // 반납 일 시 0x07 :: in stock
    // 대출상태 초기화 0x00
    @available(iOS 13.0, *)
    func writeAfi(_ iso15693Tag: NFCISO15693Tag) {
        let modeByte: UInt8 = getByteByMode(mode: self.mode)
        let writeAFI = DispatchWorkItem {
            iso15693Tag.writeAFI(requestFlags: .highDataRate,
                                 afi: modeByte,
                                 completionHandler: { (error: Error?) in
                if error != nil {
                    self.session?.invalidate(errorMessage: "Error. Change \(self.nfcSecurityMode) Flag Failed. \(modeByte.toHexString())")
                    return
                }
            })
        }
        
        let endSession = DispatchWorkItem {
            self.session?.alertMessage = "Change \(self.nfcSecurityMode) Flag Success. \(modeByte.toHexString())"
            self.session?.invalidate()
        }
        
        DispatchQueue.main.sync(execute: writeAFI)
        DispatchQueue.main.async(execute: endSession)
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
