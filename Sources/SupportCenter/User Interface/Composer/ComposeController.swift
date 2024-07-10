//
//  ComposeController.swift
//
//
//  Created by Aaron Satterfield on 5/8/20.
//

import Foundation
import UIKit
import CoreServices
import Photos

class ComposeNavigationController: UINavigationController {

    convenience init(option: ReportOption, defaultSenderEmail: String) {
        let rootViewController = ComposeViewController(option: option, defaultSenderEmail: defaultSenderEmail)
        self.init(rootViewController: rootViewController)
    }

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    override init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
        super.init(navigationBarClass: navigationBarClass, toolbarClass: toolbarClass)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

class ComposeViewController: UIViewController, AttachmentsViewDelegate {

    let option: ReportOption
    let maxAttachmentsSize = 25_000_000

    var attachments: [Attachment] = []

    lazy var attachmentsViewBottom: NSLayoutConstraint = {
        let c = self.attachmentsView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        c.priority = .required
        return c
    }()

    var email: Email? {
        didSet {
            checkSendButton()
        }
    }

    var content: String = "" {
        didSet {
            checkSendButton()
        }
    }

    lazy var emailTextField: UITextField = {
        let t = UITextField()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.textContentType = .emailAddress
        t.keyboardType = .emailAddress
        t.placeholder = "Enter your email"
        t.autocapitalizationType = .none
        t.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        t.addTarget(self, action: #selector(self.emailTextValueDidChange(sender:)), for: .editingChanged)
        t.setContentCompressionResistancePriority(.required, for: .vertical)
        t.isHidden = true // HACK 2024-07-10: we don't need this since this fork uses the user's email address for the value of email

        return t
    }()

    lazy var messageTextView: MessageTextView = {
        let v = MessageTextView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.placeholder = "Please try to be as detailed as possible."
        v.placeholderColor = .placeholderText
        v.font = UIFont.preferredFont(forTextStyle: .body)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }()

    lazy var attachmentsView: AttachmentsView = {
        let v = AttachmentsView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.attachmentsDelegate = self
        return v
    }()

    convenience init(option: ReportOption, defaultSenderEmail: String) {
        self.init(nibName: nil, bundle: nil, option: option, defaultSenderEmail: defaultSenderEmail)
    }

    init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?, option: ReportOption, defaultSenderEmail: String) {
        self.option = option
        self.email = Email(defaultSenderEmail)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = .systemBackground
        title = option.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.actionCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "paperplane.fill"), style: .done, target: self, action: #selector(actionSend(sender:)))

        setupSubviews()
        checkSendButton()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapGesture(sender:))))
        observeKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        messageTextView.becomeFirstResponder()
    }

    func setupSubviews() {
        view.addSubview(emailTextField)
        let seperator1 = SeperatorLineView()
        seperator1.backgroundColor = .clear // HACK 2024-07-10: we are hiding the EmailTextField, so don't need to show the seperator
        let seperator2 = SeperatorLineView()
        view.addSubview(seperator1)
        view.addSubview(messageTextView)
        view.addSubview(seperator2)
        view.addSubview(attachmentsView)

        NSLayoutConstraint.activate([
            emailTextField.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            emailTextField.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            emailTextField.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            seperator1.topAnchor.constraint(equalTo: emailTextField.bottomAnchor),
            seperator1.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            seperator1.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),

            messageTextView.topAnchor.constraint(equalTo: seperator1.bottomAnchor),
            messageTextView.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            messageTextView.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
        ])

        seperator2.topAnchor.constraint(greaterThanOrEqualTo: messageTextView.bottomAnchor, constant: 12.0).isActive = true
        let minSeperatorTop = seperator2.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 140.0)
        minSeperatorTop.priority = .defaultHigh
        NSLayoutConstraint.activate([minSeperatorTop])
        seperator2.leadingAnchor.constraint(equalTo: seperator1.leadingAnchor).isActive = true
        seperator2.trailingAnchor.constraint(equalTo: seperator1.trailingAnchor).isActive = true

        NSLayoutConstraint.activate([
            attachmentsView.topAnchor.constraint(equalTo: seperator2.bottomAnchor, constant: 12.0),
            attachmentsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            attachmentsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            attachmentsViewBottom
        ])

    }

    @objc func actionCancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc func actionSend(sender: UIBarButtonItem) {
        guard let senderEmail = email?.rawValue else { return }
        guard let content = messageTextView.text, !content.isEmpty else { return }
        view.endEditing(true)
        sender.isEnabled = false
        let loadingAlert = ProgressAlert(title: "Sending", message: nil, preferredStyle: .alert)
        present(loadingAlert, animated: true, completion: nil)
        SupportCenter.sendgrid?.sendSupportEmail(ofType: option, senderEmail: senderEmail, message: content, attachments: attachments, completion: { [weak self] (result) in
            loadingAlert.dismiss(animated: true, completion: {
                self?.handleSendResult(result: result, sender: sender)
            })
        })
    }

    func handleSendResult(result: SendEmailResponse, sender: UIBarButtonItem) {
        switch result {
        case .success:
            let sendAlert = self.presentAlert(title: "Success", description: "Thanks for helping to make this app better.", showDismiss: false, dismissed: nil)
            DispatchQueue.main.asyncAfter(deadline: .now()+3.0) {
                sendAlert.dismiss(animated: true, completion: {
                    self.dismiss(animated: true, completion: nil)
                })
            }
        case .failure(let error):
            print(error)
            sender.isEnabled = true
            self.presentAlert(title: "Failed to Send Feedback", description: error.localizedDescription, dismissed: nil)
        }

    }

    @objc func emailTextValueDidChange(sender: UITextField) {
        email = Email(sender.text ?? "-")
    }

    func removeAttachment(attachment: Attachment) {
        self.attachments.removeAll(where: {$0.url == attachment.url})
    }

    func checkSendButton() {
        let sendEnabled = email != nil
        navigationItem.rightBarButtonItem?.isEnabled = sendEnabled
    }

    func didSelectAddItem() {
        presentImagePicker()
    }

    @objc func onTapGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else {
            return
        }
        let location = sender.location(in: self.view)
        guard location.y > emailTextField.frame.maxY, location.y < attachmentsView.frame.minY-16 else {
            return
        }
        messageTextView.becomeFirstResponder()
    }

}

extension ComposeViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    func presentImagePicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [kUTTypeImage as String, kUTTypeMovie as String]
        present(picker, animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: { [weak self] in
            // get a thumbnail if we can
            var thumbnail = UIImage(systemName: "paperclip") ?? UIImage()
            let sem = DispatchSemaphore(value: 0)
            if let asset = info[.phAsset] as? PHAsset {
                DispatchQueue.global(qos: .utility).async {
                    let options = PHImageRequestOptions()
                    options.isNetworkAccessAllowed = true
                    let loadingAlert = ProgressAlert(title: "Loading Attachment", message: nil, preferredStyle: .alert)
                    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 210, height: 210), contentMode: .aspectFill, options: options) { (image, _) in
                        thumbnail = image ?? thumbnail
                        sem.signal()
                        DispatchQueue.main.async {
                            loadingAlert.dismiss(animated: true, completion: nil)
                        }
                    }
                }
            } else if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                thumbnail = image
                sem.signal()
            } else if let imageUrl = info[.imageURL] as? URL, let image = UIImage(contentsOfFile: imageUrl.path) {
                thumbnail = image
                sem.signal()
            } else if let mediaUrl = info[.mediaURL] as? URL, let image = self?.previewImageForLocalVideo(at: mediaUrl) {
                thumbnail = image
                sem.signal()
            } else {
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10.0)
            // get the attachment data
            if let imageUrl = info[.imageURL] as? URL,
                let attachment = Attachment(type: .image, url: imageUrl, image: thumbnail) {
                self?.addAttachment(attachment)
            } else if let videoUrl = info[.mediaURL] as? URL,
                let attachment = Attachment(type: .movie, url: videoUrl, image: thumbnail) {
                self?.addAttachment(attachment)
            } else {
                // TODO: Handle error
            }
        })
    }

    func addAttachment(_ attachment: Attachment) {
        guard attachment.size + currentAttachmentsSize() < maxAttachmentsSize else {
            self.presentAlert(title: "25MB Exceeded", description: "Attachements cannot exceed 25MB", dismissed: nil)
            return
        }
        attachments.append(attachment)
        attachmentsView.addAttachment(attachment)
    }

    func currentAttachmentsSize() -> Int {
        return attachments.map{ $0.size }.reduce(0, +)
    }

    private func previewImageForLocalVideo(at url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        var time = asset.duration
        time.value = min(time.value, 2)

        do {
            let imageRef = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: imageRef)
        } catch {
            return nil
        }
    }


}

extension ComposeViewController {

    func observeKeyboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @objc func keyboardFrameWillChange(notification: Notification) {
        guard let originalFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
             return
        }
        var keyboardFrame = originalFrame
        var viewOffset: CGFloat = 0
        if let window = view.window {
            keyboardFrame = view.convert(originalFrame, from: window.screen.coordinateSpace)
            viewOffset = window.bounds.height-view.convert(view.frame, to: window.screen.coordinateSpace).maxY
        }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: duration) {
            self.attachmentsViewBottom.constant = -(keyboardFrame.height-viewOffset + 16.0)
        }
    }

}
