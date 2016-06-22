import UIKit

public class API {
    public let baseURL: NSURL
    public var accessToken: String?

    public init(baseURL: NSURL) {
        self.baseURL = baseURL
    }

    public func URLWithPath(path: String) -> NSURL {
        return NSURL(string: path, relativeToURL: baseURL)!
    }

    public func request(HTTPMethod: String, _ path: String, _ fields: Dictionary<String, String>? = nil, _ JPEGData: NSData? = nil, authenticated: Bool = false) -> NSMutableURLRequest {
        let request = HTTP.request(HTTPMethod, URLWithPath(path), fields, JPEGData)
        if authenticated { authenticateRequest(request) }
        return request
    }

    public func authenticateRequest(request: NSMutableURLRequest) {
        request.setValue("Bearer "+accessToken!, forHTTPHeaderField: "Authorization")
    }

    public static func dataTaskWithRequest(request: NSURLRequest, completionHandler: (AnyObject?, NSHTTPURLResponse?, NSError?) -> Void) -> NSURLSessionDataTask {
        return NSURLSession.sharedSession().dataTaskWithRequest(request) { data, response, error in
            let JSONObject: AnyObject?
            let response = response as! NSHTTPURLResponse?
            let newError: NSError?

            if let error = error {
                JSONObject = nil
                newError = NSError(domain: AACNetworkingErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: error])
            } else {
                // Create newError from JSONObject if statusCode isn't successful
                JSONObject = try? NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions(rawValue: 0))
                let statusCode = response!.statusCode; let isResponseSuccessful = (200 <= statusCode && statusCode <= 299)
                newError = !isResponseSuccessful ? errorWithDictionary(JSONObject as! Dictionary<String, String>?, statusCode: statusCode) : nil
            }

            completionHandler(JSONObject, response, newError)
        }
    }

    public static func errorWithDictionary(dictionary: Dictionary<String, String>?, statusCode: Int) -> NSError {
        let title = dictionary?["title"] ?? NSHTTPURLResponse.anb_localizedClassForStatusCode(statusCode).localizedCapitalizedString
        let reasonPhrase = NSHTTPURLResponse.localizedStringForStatusCode(statusCode).localizedCapitalizedString
        var message = reasonPhrase == title ? "\(statusCode) Status Code" : "\(statusCode) \(reasonPhrase)"
        if let serverMessage = dictionary?["message"] { message += ": \(serverMessage)" }
        var userInfo = [AACNetworkingErrorTitleKey: title, AACNetworkingErrorMessageKey: message]
        return NSError(domain: AACNetworkingErrorDomain, code: statusCode, userInfo: userInfo)
    }
}

public class HTTP {
    public static func request(HTTPMethod: String, _ URL: NSURL, _ fields: Dictionary<String, String>? = nil, _ JPEGData: NSData? = nil) -> NSMutableURLRequest {
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = HTTPMethod

        guard let JPEGData = JPEGData else {
            if let fields = fields {
                request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.HTTPBody = formHTTPBodyFromFields(fields)
            }
            return request
        }

        let boundary = multipartBoundary()
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = multipartBodyData(boundary, fields, JPEGData)
        return request
    }

    // Convert ["name1": "value1", "name2": "value2"] to "name1=value1&name2=value2".
    // NOTE: Like curl: Let front-end developers URL encode names & values.
    public static func formHTTPBodyFromFields(fields: Dictionary<String, String>) -> NSData? {
        var bodyArray = [String]()
        for (name, value) in fields {
            bodyArray.append("\(name)=\(value)")
        }
        return bodyArray.joinWithSeparator("&").dataUsingEncoding(NSUTF8StringEncoding)
    }

    private static func multipartBoundary() -> String {
        return "-----AcaniFormBoundary" + String.randomStringWithLength(16)
    }

    private static func multipartBodyData(boundary: String, _ fields: Dictionary<String, String>? = nil, _ JPEGData: NSData) -> NSData {
        var bodyString = ""
        let hh = "--", rn = "\r\n"

        func contentDisposition(name: String) -> String {
            return "Content-Disposition: form-data; name=\"\(name)\""
        }

        // Add fields
        if let fields = fields {
            for (name, value) in fields {
                bodyString += hh + boundary + rn
                bodyString += contentDisposition(name) + rn + rn
                bodyString += value + rn
            }
        }

        // Add JPEG data
        bodyString += hh + boundary + rn
        bodyString += contentDisposition("jpeg") + rn
        bodyString += "Content-Type: image/jpeg" + rn + rn
        let bodyData = NSMutableData(data: bodyString.dataUsingEncoding(NSUTF8StringEncoding)!)
        bodyData.appendData(JPEGData)

        // Complete
        bodyString = rn + hh + boundary + hh + rn
        bodyData.appendData(bodyString.dataUsingEncoding(NSUTF8StringEncoding)!)

        return bodyData
    }
}

extension NSHTTPURLResponse {
    public class func anb_localizedClassForStatusCode(statusCode: Int) -> String {
        let statusCodeClass = statusCode - (statusCode % 100) + 99 // e.g.: 404 becomes 499
        return localizedStringForStatusCode(statusCodeClass)
    }
}

extension String {
    public static func randomStringWithLength(length: Int) -> String {
        let alphabet = "-_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" // 64 characters
        return String((0..<length).map { _ -> Character in
            return alphabet[alphabet.startIndex.advancedBy(Int(arc4random_uniform(64)))]  // <^ connected
        })
    }

    // Percent encode all characters except alphanumerics, "*", "-", ".", and "_". Replace " " with "+".
    // http://www.w3.org/TR/html5/forms.html#application/x-www-form-urlencoded-encoding-algorithm
    public func stringByAddingFormURLEncoding() -> String {
        let characterSet = NSMutableCharacterSet.alphanumericCharacterSet()
        characterSet.addCharactersInString("*-._ ")
        return stringByAddingPercentEncodingWithAllowedCharacters(characterSet)!.stringByReplacingOccurrencesOfString(" ", withString: "+")
    }
}

import Alerts

public func alertNetworkingError(error: NSError, handler: ((UIAlertAction) -> Void)? = nil) {
    func messageWithError(error: NSError) -> String {
        var message: String?
        if let errorDescription = error.userInfo[NSLocalizedDescriptionKey] as! String? {
            message = errorDescription
        }
        if let recoverySuggestion = error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as! String? {
            message = message != nil ? "\(message!) \(recoverySuggestion)" : recoverySuggestion
        }
        if message == nil { message = error.localizedDescription }
        return message!
    }

    var title: String?
    var message: String?
    if error.userInfo.indexForKey(NSUnderlyingErrorKey) != nil {
        title = "Networking Error"
        message = messageWithError(error)
    } else {
        title = error.userInfo[AACNetworkingErrorTitleKey] as! String? ?? ""
        message = error.userInfo[AACNetworkingErrorMessageKey] as! String?
    }
    alert(title: title, message: message, handler: handler)
}

public let AACNetworkingErrorDomain = "AACNetworkingErrorDomain"

public let AACNetworkingErrorTitleKey   = "AACNetworkingErrorTitleKey"
public let AACNetworkingErrorMessageKey = "AACNetworkingErrorMessageKey"
