//
//  ShareViewController.swift
//  RNShareMenu
//
//  DO NOT EDIT THIS FILE. IT WILL BE OVERRIDEN BY NPM OR YARN.
//
//  Created by Gustavo Parreira on 26/07/2020.
//
//  Modified by Veselin Stoyanov on 17/04/2021.

import Foundation
import MobileCoreServices
import UIKit
import Social
import RNShareMenu
import os.log

@available(iOSApplicationExtension, unavailable)
class ShareViewController: SLComposeServiceViewController {
  var hostAppId: String?
  var hostAppUrlScheme: String?
  var sharedItems: [Any] = []
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    if let hostAppId = Bundle.main.object(forInfoDictionaryKey: HOST_APP_IDENTIFIER_INFO_PLIST_KEY) as? String {
      self.hostAppId = hostAppId
    } else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
    }
    
    if let hostAppUrlScheme = Bundle.main.object(forInfoDictionaryKey: HOST_URL_SCHEME_INFO_PLIST_KEY) as? String {
      self.hostAppUrlScheme = hostAppUrlScheme
    } else {
      print("Error: \(NO_INFO_PLIST_URL_SCHEME_ERROR)")
    }
  }

  override func isContentValid() -> Bool {
      // Do validation of contentText and/or NSExtensionContext attachments here
      return true
  }

  override func didSelectPost() {
      // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      cancelRequest()
      return
    }

    handlePost(items)
  }

  override func configurationItems() -> [Any]! {
      // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
      didSelectPost()
      return nil
  }

  func handlePost(_ items: [NSExtensionItem], extraData: [String:Any]? = nil) {
    DispatchQueue.global().async {

      NSLog("ShareViewController: handlePost %@",items)

      guard let hostAppId = self.hostAppId else {
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }
      
      guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId)") else {
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }

      if let data = extraData {
        self.storeExtraData(data)
      } else {
        self.removeExtraData()
      }
      
      let semaphore = DispatchSemaphore(value: 0)
      var results: [Any] = []

      for item in items {
        NSLog("ShareViewController: handlePost item %@", item)
        guard let attachments = item.attachments else {
          self.cancelRequest()
          return
        }
        NSLog("ShareViewController: handlePost attachments %@", attachments)

        for provider in attachments {
          NSLog("ShareViewController: handlePost provider %@", provider)

          if provider.isText {
            NSLog("ShareViewController: handlePost isText")
            self.storeText(withProvider: provider, semaphore)
          } else if provider.isImage {
            NSLog("ShareViewController: handlePost isImage")
            self.storeImage(withProvider: provider, semaphore)
          } else if provider.isURL {
            NSLog("ShareViewController: handlePost isURL")
            self.storeLinkUrl(withProvider: provider, semaphore)
          } else {
            NSLog("ShareViewController: handlePost isOther (file)")
            self.storeFile(withProvider: provider, semaphore)
          }

          semaphore.wait()
        }
      }

      userDefaults.set(self.sharedItems,
                       forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()

      NSLog("ShareViewController: handlePost finished")

      self.openHostApp()
    }
  }

  func storeExtraData(_ data: [String:Any]) {
    guard let hostAppId = self.hostAppId else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
      return
    }
    guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId)") else {
      print("Error: \(NO_APP_GROUP_ERROR)")
      return
    }
    userDefaults.set(data, forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
    userDefaults.synchronize()
  }

  func storeLinkUrl(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (data, error) in
      guard (error == nil) else {
        self.exit(withError: error.debugDescription)
        return
      }
      guard let url = data as? URL else {
        self.exit(withError: COULD_NOT_FIND_URL_ERROR)
        return
      }
      
      self.sharedItems.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: "text/plain"])
      semaphore.signal()
    }
  }

  func removeExtraData() {
    guard let hostAppId = self.hostAppId else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
      return
    }
    guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId)") else {
      print("Error: \(NO_APP_GROUP_ERROR)")
      return
    }
    userDefaults.removeObject(forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
    userDefaults.synchronize()
  }
  
  func storeText(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) { (data, error) in
      guard (error == nil) else {
        self.exit(withError: error.debugDescription)
        return
      }
      guard let text = data as? NSData else{
        guard let text = data as? String else {
          self.exit(withError: COULD_NOT_FIND_STRING_ERROR)
          return
        }
        
        self.sharedItems.append([DATA_KEY: text, MIME_TYPE_KEY: "text/plain"])
        semaphore.signal()
        return
      }
      let url = String(data: text as Data, encoding: .utf8)
      self.sharedItems.append([DATA_KEY: url, MIME_TYPE_KEY: "vcard"])
      semaphore.signal()
    }
  }
  
  func storeUrl(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (data, error) in
 
      NSLog("ShareViewController: storeUrl provider %@", provider)

      guard (error == nil) else {
        NSLog("ShareViewController: ERROR %@", error.debugDescription)

        self.exit(withError: error.debugDescription)
        return
      }
      guard let url = data as? URL else {
        NSLog("ShareViewController: storeUrl url ERROR %@", COULD_NOT_FIND_URL_ERROR)

        self.exit(withError: COULD_NOT_FIND_URL_ERROR)
        return
      }

      let mimeType = url.extractMimeType()
      NSLog("ShareViewController: storeUrl url.absoluteString %@", url.absoluteString)
      NSLog("ShareViewController: storeUrl  mimeType %@", mimeType)

      guard let hostAppId = self.hostAppId else {
        NSLog("ShareViewController: storeUrl hostAppId ERROR %@", NO_INFO_PLIST_INDENTIFIER_ERROR)
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }

      guard let groupFileManagerContainer = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostAppId)")
      else {
        NSLog("ShareViewController: storeUrl groupFileManagerContainer ERROR:  %@", NO_APP_GROUP_ERROR)
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }

      let fileExtension = url.pathExtension
      let fileName = UUID().uuidString
      let filePath = groupFileManagerContainer
        .appendingPathComponent("\(fileName).\(fileExtension)")
        
      NSLog("ShareViewController: storeUrl  filePath.absoluteString %@", filePath.absoluteString)
      NSLog("ShareViewController: storeUrl  filePath.path %@", filePath.path)

      let resultCopy = self.moveFileToDisk(from: url, to: filePath)
      NSLog("ShareViewController: storeUrl resultCopy")

      self.sharedItems.append([DATA_KEY: filePath.absoluteString, MIME_TYPE_KEY: mimeType])
      semaphore.signal()
    }
  }
  
  /**
  * Images can be provided in two types: URL or UIImage.
  * We check here the type and call storeFile for url and storeImageRawData for uiimage
  */
  func storeImage(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    NSLog("ShareViewController: storeImage provider %@", provider)
    provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (data, error) in

      NSLog("ShareViewController: storeImage data %@", "\(data)")

      guard (error == nil) else {
        NSLog("ShareViewController: storeImage error %@", error.debugDescription)
        self.exit(withError: error.debugDescription)
        return
      }
      
      if data as? URL != nil {
        self.storeFile(withProvider: provider, semaphore)
      }
      else if data as? UIImage != nil {
        self.storeImageRawData(withProvider: provider, semaphore)
      }
      else {
        self.exit(withError: "ShareViewController: storeImage  - data type unknown")
      }
    }
  }

  /**
  * Take an URL as input
  */
  func storeFile(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    NSLog("ShareViewController: storeFile provider %@", provider)
    provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (data, error) in

      NSLog("ShareViewController: storeFile data %@", "\(data)")

      guard (error == nil) else {
        NSLog("ShareViewController: storeFile error %@", error.debugDescription)
        self.exit(withError: error.debugDescription)
        return
      }
      guard let url = data as? URL else {
        NSLog("ShareViewController: storeFile error %@", COULD_NOT_FIND_IMG_ERROR)
        self.exit(withError: COULD_NOT_FIND_IMG_ERROR)
        return
      }
      guard let hostAppId = self.hostAppId else {
        NSLog("ShareViewController: storeFile error %@", NO_INFO_PLIST_INDENTIFIER_ERROR)
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }

      guard let groupFileManagerContainer = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostAppId)")
      else {
        NSLog("ShareViewController: storeFile error %@", NO_APP_GROUP_ERROR)
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }

      NSLog("ShareViewController: storeFile url path %@", url.path)

      let mimeType = url.extractMimeType()
      NSLog("ShareViewController: storeFile  mimeType %@", mimeType)
      let fileExtension = url.pathExtension
      let fileName = UUID().uuidString
      let filePath = groupFileManagerContainer
        .appendingPathComponent("\(fileName).\(fileExtension)")
      NSLog("ShareViewController: storeFile  fileName %@", fileName)

      guard self.moveFileToDisk(from: url, to: filePath) else {
        NSLog("ShareViewController: storeFile  error %@", COULD_NOT_SAVE_FILE_ERROR)
        self.exit(withError: COULD_NOT_SAVE_FILE_ERROR)
        return
      }

      self.sharedItems.append([DATA_KEY: filePath.absoluteString, MIME_TYPE_KEY: mimeType])
      NSLog("ShareViewController: storeFile end")

      semaphore.signal()
    }
  }
  
  /**
  * Takes an UIImage as input, converts it to NSData and saves it to jpeg file
  */
  func storeImageRawData(withProvider provider: NSItemProvider, _ semaphore: DispatchSemaphore) {
    NSLog("ShareViewController: storeImageRawData provider %@", provider)
    provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (data, error) in

      NSLog("ShareViewController: storeImageRawData data %@", "\(data)")

      guard (error == nil) else {
        NSLog("ShareViewController: storeImageRawData error %@", error.debugDescription)
        self.exit(withError: error.debugDescription)
        return
      }
      guard let uiImage = data as? UIImage else {
        NSLog("ShareViewController: storeImageRawData uiImage %@", COULD_NOT_FIND_IMG_ERROR)
        self.exit(withError: COULD_NOT_FIND_IMG_ERROR)
        return
      }
      guard let hostAppId = self.hostAppId else {
        NSLog("ShareViewController: storeImageRawData hostAppId %@", NO_INFO_PLIST_INDENTIFIER_ERROR)
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }

      guard let groupFileManagerContainer = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostAppId)")
      else {
        NSLog("ShareViewController: storeImageRawData groupFileManagerContainer %@", NO_APP_GROUP_ERROR)
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }

      let fileExtension = "jpg"
      let fileName = UUID().uuidString
      let filePath = groupFileManagerContainer
        .appendingPathComponent("\(fileName).\(fileExtension)")
      NSLog("ShareViewController: storeImageRawData  fileName %@", fileName)

      guard let rawData = uiImage.jpegData(compressionQuality:1.0)
      else {
        NSLog("ShareViewController: storeImageRawData Error while getting raw data")
        self.exit(withError: "Error while getting raw data")
        return
      }
      
      guard self.copyRawDataToFile(data:rawData, to: filePath)
      else {
        NSLog("ShareViewController: storeImageRawData Error while copying raw data")
        self.exit(withError: "Error while copying raw data")
        return
      }
      
      self.sharedItems.append([DATA_KEY: filePath.absoluteString, MIME_TYPE_KEY: "image/jpeg"])
      NSLog("ShareViewController: storeImageRawData end")

      semaphore.signal()
    }
  }

  func moveFileToDisk(from srcUrl: URL, to destUrl: URL) -> Bool {
    NSLog("ShareViewController: moveFileToDisk")

    do {
      if FileManager.default.fileExists(atPath: destUrl.path) {
        try FileManager.default.removeItem(at: destUrl)
      }
      try FileManager.default.copyItem(at: srcUrl, to: destUrl)
    } catch (let error) {
      NSLog("ShareViewController: moveFileToDisk - error while copyItem %@", "\(error)")

      // print("Could not save file from \(srcUrl) to \(destUrl): \(error)")
      return false
    }
          
    NSLog("ShareViewController: moveFileToDisk end")

    return true
  }

  func copyRawDataToFile(data rawData: Data, to destUrl: URL) -> Bool {
    NSLog("ShareViewController: copyRawDataToFile")

    guard FileManager.default.createFile(atPath: destUrl.path, contents: rawData)
    else {
      NSLog("ShareViewController: copyRawDataToFile - Error while createFile")
      self.exit(withError: "Error while createFile")
      return false
    }
   
    NSLog("ShareViewController: copyRawDataToFile end")

    return true
  }
  
  func exit(withError error: String) {
    print("Error: \(error)")
    cancelRequest()
  }
  
  internal func openHostApp() {
    NSLog("ShareViewController: openHostApp")

    guard let urlScheme = self.hostAppUrlScheme else {
      exit(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }

    guard let url = URL(string: urlScheme) else {
      exit(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
 
    UIApplication.shared.open(url, options: [:], completionHandler: completeRequest)

    // let url = URL(string: urlScheme)
    // let selectorOpenURL = sel_registerName("openURL:")
    // var responder: UIResponder? = self

    // while responder != nil {
    //   if responder?.responds(to: selectorOpenURL) == true {
    //     responder?.perform(selectorOpenURL, with: url)
    //   }
    //   responder = responder!.next
    // }
    // NSLog("ShareViewController: openHostApp end")

    // completeRequest()
  }
  
  func completeRequest(success: Bool) {
    // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
    extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
  }
  
  func cancelRequest() {
    extensionContext!.cancelRequest(withError: NSError())
  }

}
