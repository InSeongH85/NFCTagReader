//
//  ViewController+DataSource.swift
//  NFCReader
//
//  Created by InSeongHwang on 2021/07/23.
//
import UIKit
import CoreNFC

extension ViewController {
  
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return self.barcodeSet.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier)!
    if let cell = cell as? CustomCell {
      DispatchQueue.main.async {
        cell.customLabel?.text = self.barcodeSet[indexPath.row]
        cell.stateLabel?.text = self.currentStatus
      }
    }
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      print("You tapped cell number \(indexPath.row).")
  }

  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
      if editingStyle == .delete {
          barcodeSet.remove(at: indexPath.row)
          tableView.deleteRows(at: [indexPath], with: .fade)
      }
  }

}
