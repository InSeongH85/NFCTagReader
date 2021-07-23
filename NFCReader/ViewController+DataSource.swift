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
    // create a new cell if needed or reuse an old one
    let cell:UITableViewCell = (self.tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier) as UITableViewCell?)!
    // set the text from the data model
    cell.textLabel?.text = self.barcodeSet[indexPath.row]
    return cell
  }

  // method to run when table view cell is tapped
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      print("You tapped cell number \(indexPath.row).")
  }

  // this method handles row deletion
  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
      if editingStyle == .delete {
          // remove the item from the data model
          barcodeSet.remove(at: indexPath.row)
          // delete the table view row
          tableView.deleteRows(at: [indexPath], with: .fade)
      }
  }

}
