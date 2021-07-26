import UIKit

class CustomCell: UITableViewCell {
    var yourobj : ((String) -> Void)? = nil

   //You can pass any kind data also.
   var user: ((String?) -> Void)? = nil
    override func awakeFromNib() {
      super.awakeFromNib()
    }

  @IBAction func btnAction(sender: UIButton) {
    if let btnAction = self.yourobj
    {
        btnAction("TEST")
        user!("pass string")
    }
  }
}
