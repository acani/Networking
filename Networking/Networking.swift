import UIKit

open class API {
    open let baseURL: URL
    open var accessToken: String?

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    open func request(_ HTTPMethod: String, _ path: String, _ fields: Dictionary<String, String>? = nil, _ JPEGData: Data? = nil, authenticated: Bool = false) -> URLRequest {
        var request = HTTP.request(HTTPMethod, URL(string: path, relativeTo: baseURL)!, fields, JPEGData)
        if authenticated { request.setValue("Bearer "+accessToken!, forHTTPHeaderField: "Authorization") }
        return request
    }

    open static func dataTask(with request: URLRequest, completionHandler: @escaping (AnyObject?, HTTPURLResponse?, NetworkingError?) -> Swift.Void) -> URLSessionDataTask {
        HTTP.networkActivityIndicatorVisible = true
        return URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            let object: AnyObject?
            let response = response as! HTTPURLResponse?
            let newError: NetworkingError?

            if let error = error {
                object = nil
                newError = NetworkingError(error: error as NSError)
            } else {
                // Create newError from object if statusCode isn't successful
                object = data!.isEmpty ? nil : try! JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: 0)) as AnyObject?
                let statusCode = response!.statusCode; let isResponseSuccessful = (200 <= statusCode && statusCode <= 299)
                newError = !isResponseSuccessful ? NetworkingError(dictionary: object as! Dictionary<String, String>?, statusCode: statusCode) : nil
            }

            completionHandler(object, response, newError)
            HTTP.networkActivityIndicatorVisible = false
        }) 
    }
}

open class HTTP {
    private static var networkActivityCount: Int = 0

    open static var networkActivityIndicatorVisible: Bool {
        get { return networkActivityCount > 0 }
        set(visible) {
            networkActivityCount += visible ? 1 : -1
            assert(networkActivityCount >= 0)
            DispatchQueue.main.async {
                UIApplication.shared.isNetworkActivityIndicatorVisible = (networkActivityCount > 0)
            }
        }
    }

    open static func request(_ HTTPMethod: String, _ URL: Foundation.URL, _ fields: Dictionary<String, String>? = nil, _ JPEGData: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL)
        request.httpMethod = HTTPMethod

        guard let JPEGData = JPEGData else {
            if let fields = fields {
                request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = formHTTPBody(withFields: fields)
            }
            return request
        }

        let boundary = multipartBoundary()
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBodyData(boundary, fields, JPEGData)
        return request
    }

    // Convert ["name1": "value1", "name2": "value2"] to "name1=value1&name2=value2".
    // NOTE: Like curl: Let front-end developers URL encode names & values.
    open static func formHTTPBody(withFields fields: Dictionary<String, String>) -> Data? {
        var bodyArray = [String]()
        for (name, value) in fields {
            bodyArray.append("\(name)=\(value.anw_addingFormURLEncoding)")
        }
        return bodyArray.joined(separator: "&").data(using: .utf8)
    }

    private static func multipartBoundary() -> String {
        return "-----AcaniFormBoundary" + String.anw_random(withLength: 16)
    }

    private static func multipartBodyData(_ boundary: String, _ fields: Dictionary<String, String>? = nil, _ JPEGData: Data) -> Data {
        var bodyString = ""
        let hh = "--", rn = "\r\n"

        func contentDisposition(_ name: String) -> String {
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
        var bodyData = bodyString.data(using: .utf8)!
        bodyData.append(JPEGData)

        // Complete
        bodyString = rn + hh + boundary + hh + rn
        bodyData.append(bodyString.data(using: .utf8)!)

        return bodyData
    }
}

extension HTTPURLResponse {
    public class func anb_localizedClass(forStatusCode statusCode: Int) -> String {
        let statusCodeClass = statusCode - (statusCode % 100) + 99 // e.g.: 404 becomes 499
        return localizedString(forStatusCode: statusCodeClass)
    }
}

extension String {
    public static func anw_random(withLength length: Int) -> String {
        let alphabet = "-_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" // 64 characters
        return String((0..<length).map { _ -> Character in
            return alphabet[alphabet.characters.index(alphabet.startIndex, offsetBy: Int(arc4random_uniform(64)))]  // <^ connected
        })
    }

    // Percent encode all characters except alphanumerics, "*", "-", ".", and "_". Replace " " with "+".
    // http://www.w3.org/TR/html5/forms.html#application/x-www-form-urlencoded-encoding-algorithm
    public var anw_addingFormURLEncoding: String {
        let characterSet = NSMutableCharacterSet.alphanumeric()
        characterSet.addCharacters(in: "*-._ ")
        return addingPercentEncoding(withAllowedCharacters: characterSet as CharacterSet)!.replacingOccurrences(of: " ", with: "+")
    }
}

public struct NetworkingError: Error {
    public enum ErrorType {
        case taskError
        case badStatus
    }
    public let title: String
    public let message: String
    public let type: ErrorType
    public let code: Int
    public var isUnauthorized: Bool { return type == .badStatus && code == 401 }
    public var isForbidden: Bool { return type == .badStatus && code == 403 }

    public init(error: NSError) {
        title = "Networking Error"
        message = error.localizedDescription
        type = .taskError
        code = error.code
    }

    public init(dictionary: Dictionary<String, String>?, statusCode: Int) {
        title = dictionary?["title"] ?? HTTPURLResponse.anb_localizedClass(forStatusCode: statusCode).localizedCapitalized
        let reasonPhrase = HTTPURLResponse.localizedString(forStatusCode: statusCode).localizedCapitalized
        var mutableMessage = reasonPhrase == title ? "\(statusCode) Status Code" : "\(statusCode) \(reasonPhrase)"
        if let serverMessage = dictionary?["message"] { mutableMessage += ": \(serverMessage)" }
        message = mutableMessage
        type = .badStatus
        code = statusCode
    }
}

import Alerts

public func alertNetworkingError(_ error: NetworkingError, handler: ((UIAlertAction) -> Swift.Void)? = nil) {
    alertTitle(error.title, message: error.message, handler: handler)
}
