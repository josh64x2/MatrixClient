/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Cocoa
import SwiftMatrixSDK

extension NSTextField {
    func height(forWidth width: CGFloat) -> CGFloat {
        return stringValue.height(forWidth: width, withFont: self.font)
    }
}

extension String {
    func height(forWidth width: CGFloat, withFont font: NSFont!) -> CGFloat {
        let size = CGSize(width: width, height: 0)
        let attributes:[String : Any]? = [NSFontAttributeName: font]
        let boundingRect = (self as NSString).boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        return boundingRect.height
    }
}


extension Array {
    
    func filterDuplicates(includeElement: (_ lhs:Element, _ rhs:Element) -> Bool) -> [Element]{
        var results = [Element]()
        
        forEach { (element) in
            let existingElements = results.filter {
                return includeElement(element, $0)
            }
            if existingElements.count == 0 {
                results.append(element)
            }
        }
        
        return results
    }
}

@objc protocol RoomFetchDelegate : class {
    func roomFetcher(_ fetcher: ViewController, didFetch rooms: [MXRoom])
}

class MatrixMessage : NSObject {
    var event: MXEvent
    
    var text: String { return (event.content["body"] as? String) ?? "" }
    var sender: String { return event.sender }
    var age: UInt64 { return event.ageLocalTs }
    
    var id: String { return event.eventId }
    
    init(event: MXEvent) {
        self.event = event
    }
}

class MessageCellView : NSTableCellView {
    @IBOutlet weak var messageLabel: NSTextField!
    @IBOutlet weak var senderLabel: NSTextField?
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var avatarImageView: NSImageView?
    
    override func awakeFromNib() {
        self.wantsLayer = true
        self.layer?.masksToBounds = false
    }
}

class ViewController: NSViewController, RoomChangedDelegate, MatrixSessionManagerDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTextViewDelegate {
    
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var messageTextView: NSTextView!
    @IBOutlet weak var messageTextViewVerticalSizeConstraint: NSLayoutConstraint!
    @IBOutlet weak var titleLabel: NSTextField!
    
    var currentRoom: MXRoom?
    var imageProvider: ImageProvider = ImageProvider()
    
    private var sortedRoomMessages = [MatrixMessage]()
    var roomMessages: [MatrixMessage] {
        get { return sortedRoomMessages }
        set {
            let deDupedMessages = newValue.filterDuplicates { return $0.id == $1.id }
            sortedRoomMessages = deDupedMessages.sorted(by: { return $0.age < $1.age })
        }
    }
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let sideBarController = self.parent?.childViewControllers.flatMap({ return $0 as? SidebarController }).first {
            sideBarController.roomChangedDelegate = self
        }
        
        tableView.tableColumns.first?.width = tableView.bounds.width
        tableView.rowHeight = 60;
        
        titleLabel.stringValue = ""
        
        reloadContentInsets()
    }
    
    func reloadContentInsets() {
        tableView.enclosingScrollView?.contentInsets.bottom = messageTextViewVerticalSizeConstraint.constant + 16
        tableView.enclosingScrollView?.contentInsets.top = 60
    }
    
    
    func matrixDidStart(_ session: MXSession) {
        
    }
    
    func matrixDidLogout() {
        roomMessages = []
        currentRoom?.liveTimeline.removeAllListeners()
        currentRoom = nil
        
        tableView.reloadData()
    }
    

    func roomChanger(_ changer: SidebarController, setRoom room: MXRoom) {
        currentRoom = room
        titleLabel.stringValue = room.state.name ?? room.state.canonicalAlias ?? "Unnamed Room"
        
        print("Listening to \(room.roomId)")
        sortedRoomMessages = []
        tableView.reloadData()
        
        room.liveTimeline.resetPagination()
        _ = room.liveTimeline.listenToEvents([.roomMessage]) { (event, direction, roomState) in
            
            // Check to see if the scroll view is scrolled to the bottom
            self.roomMessages.append(MatrixMessage(event: event))
            self.tableView.reloadData()
            self.scrollView.documentView?.scrollToEndOfDocument(self)
        }
        
        _ = room.liveTimeline.listenToEvents([.typing]) { (event, direction, roomState) in
            
            let typingUsers = room.typingUsers ?? []
            if typingUsers.count > 0 {
                
            } else {
                
            }
        }
        
        _ = room.liveTimeline.listenToEvents { (event, direction, roomState) in
            print(event)
        }
        
        room.liveTimeline.paginate(10, direction: .backwards, onlyFromStore: false) { response in
            
        }
        
        room.state.members.forEach { (member) in
            print(member.displayname ?? member.userId!)
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    
    
    
    
    func submitMessage() {
        guard let stringValue = messageTextView.string else { return }
        messageTextView.textStorage?.mutableString.setString("")
        
        guard let room = currentRoom else { return }
        room.mxSession.matrixRestClient.sendTextMessage(toRoom: room.roomId, text: stringValue) { (response) in
            switch response {
            case .success:
                print("Go")
            case .failure:
                print("Fail")
            }
        }
    }
    
    
    override func viewDidLayout() {
        self.tableView.reloadData()
    }
    
    
    // MARK: - NSTableViewDatasource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return roomMessages.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return roomMessages[row]
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let message = roomMessages[row]
        let previousMessage: MatrixMessage? = (row > 0 ? roomMessages[row-1] : nil)
        let myUserId = MatrixSessionManager.shared.session?.matrixRestClient?.credentials?.userId
        
        let cellIdentifier: String
        if message.sender == myUserId {
            // This message was sent by the user
            cellIdentifier = "SentMessageCell";
        } else if message.sender == previousMessage?.sender {
            // This message was received, but the sender is the same as before,
            // so we don't need to show the username.
            cellIdentifier = "ReceivedMessageCell"
        } else {
            // This is a different sender from before, so show the username.
            cellIdentifier = "ReceivedMessageCellWithSender"
        }
        
        
        let cell = tableView.make(withIdentifier: cellIdentifier, owner: self) as? MessageCellView
        cell?.messageLabel?.stringValue = message.text
        cell?.senderLabel?.stringValue = message.sender
        
        let date = Date(timeIntervalSince1970: Double(message.age) / 1000)
        let dateFormatter = DateFormatter()
        if let previousMessage = previousMessage {
            let previousDate = Date(timeIntervalSince1970: Double(previousMessage.age) / 1000)
            
            // If the date changed, show the date and the time.
            let dateOnly = DateFormatter()
            dateOnly.timeStyle = .none
            dateOnly.dateStyle = .short
            
            let dateTime = DateFormatter()
            dateTime.timeStyle = .short
            dateTime.dateStyle = .short
            
            if (dateOnly.string(from: date) != dateOnly.string(from: previousDate)) {
                dateFormatter.timeStyle = .short
                dateFormatter.dateStyle = .short
            } else if (dateTime.string(from: date) != dateTime.string(from: previousDate)) {
                dateFormatter.timeStyle = .short
                dateFormatter.dateStyle = .none
            } else {
                dateFormatter.timeStyle = .none
                dateFormatter.dateStyle = .none
            }
            
        } else {
            dateFormatter.timeStyle = .short
            dateFormatter.dateStyle = .short
        }
        cell?.dateLabel?.stringValue = dateFormatter.string(from: date)
        
        if  let senderUser = MatrixSessionManager.shared.session?.user(withUserId: message.sender),
            let avatarUrlString = senderUser.avatarUrl,
            let avatarUrl = URL(string: avatarUrlString)?.resolvingMatrixUrl() {
            
            if let image = imageProvider.cachedImage(for: avatarUrl) {
                cell?.avatarImageView?.image = image
            } else {
                imageProvider.image(for: avatarUrl) { response in
                    switch response {
                    case .success(let image):
                        
                        // The cell might have moved. Make sure we're accessing the right cell.
                        let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageCellView
                        cell?.avatarImageView?.image = image
                        
                    default: break
                    }
                }
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let message = roomMessages[row]
        let previousMessage: MatrixMessage? = (row > 0 ? roomMessages[row-1] : nil)
        let myUserId = MatrixSessionManager.shared.session?.matrixRestClient?.credentials?.userId
        
        let maxMessageWidth = tableView.bounds.width - 100 /* The left margin of the bubble */ - 21 /* The margin around the text */  - 3 /* ??? */;
        
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize())
        let textHeight = message.text.height(forWidth: maxMessageWidth, withFont: font)
        
        let cellHeight: CGFloat
        if message.sender != previousMessage?.sender && message.sender != myUserId {
            cellHeight = textHeight + 8 + 15
        } else {
            cellHeight = textHeight + 8
        }
        
        return cellHeight
    }
    
    
    
    
    
    
    func textDidEndEditing(_ notification: Notification) {
        Swift.print("Did End editing: \(notification)")
        // Check to see if this was a return key press
        if (notification.userInfo?["NSTextMovement"] as? Int) == NSReturnTextMovement {
            submitMessage()
            messageTextView.window?.makeFirstResponder(messageTextView)
        }
    }
    
    func textDidChange(_ notification: Notification) {
        
        guard
            let textContainer = messageTextView.textContainer,
            let layoutManager = messageTextView.layoutManager
            else { return }
        
        let height = layoutManager.usedRect(for: textContainer).height
        messageTextViewVerticalSizeConstraint.constant = height
        reloadContentInsets()
        self.view.layout()
    }
}

