import UIKit

open class API {
  public let session: URLSession
  public let baseURL: URL
  public let versionPath: String?
  public let credentials: String
  open var accessToken: String?
  open var refreshToken: String?
  weak var refreshAccessTokenDataTask: URLSessionDataTask?
  open var queuedRequests: [(URLRequest, (Any?, HTTPURLResponse?, NetworkingError?) -> Swift.Void)]

  public init(baseURL: URL, versionPath: String? = nil, credentials: String) {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 33
    session = URLSession(configuration: configuration)
    self.baseURL = baseURL
    self.versionPath = versionPath
    self.credentials = credentials
    queuedRequests = []
  }

  open func request(_ HTTPMethod: String, _ path: String, _ fields: [String: String]? = nil, _ JPEGData: Data? = nil, authenticated: Bool = false) -> URLRequest {
    let versionedPath = versionPath != nil ? versionPath!+path : path
    let requestURL = URL(string: versionedPath, relativeTo: baseURL)!
    var request = HTTP.request(HTTPMethod, requestURL, fields, JPEGData)
    if !authenticated {
      request.anw_setBasicAuth(with: credentials)
    } else {
      request.anw_setAccessToken(accessToken!)
    }
    return request
  }

  open func dataTask(with request: URLRequest, completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Swift.Void) -> URLSessionDataTask {
    HTTP.networkActivityIndicatorVisible = true
    return session.dataTask(with: request) { data, response, error in
      let object: Any?
      let httpResponse = response as! HTTPURLResponse?
      let networkingError: NetworkingError?

      if let error = error {
        object = nil
        networkingError = NetworkingError(error: error as NSError)
      } else {
        if let jsonObject = self.parseJSON(with: data!) {
          object = jsonObject
          if httpResponse!.anw_isUserUnauthenticated {
            return self.refreshAccessTokenAndRetryRequest(request, completionHandler: completionHandler)
          }
        } else {
          object = self.errorMessageDictionary(with: data!)
        }
        if httpResponse!.anw_hasErrorStatusCode {
          if let dictionary = object! as? [String: String] {
            networkingError = NetworkingError(dictionary: dictionary, response: httpResponse!)
          } else {
            networkingError = NetworkingError(statusCode: httpResponse!.statusCode)
          }
        } else {
          networkingError = nil
        }
      }

      completionHandler(object, httpResponse, networkingError)
      HTTP.networkActivityIndicatorVisible = false
    }
  }

  private func refreshAccessTokenAndRetryRequest(_ request: URLRequest, completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Swift.Void) {
    queuedRequests.append((request, completionHandler))
    guard refreshAccessTokenDataTask == nil || refreshAccessTokenDataTask!.state == .completed else { return }
    let refreshRequest = self.request("PUT", "/sessions", ["refresh_token": refreshToken!])
    refreshAccessTokenDataTask = baseDataTask(with: refreshRequest) { object, response, error in
      if let error = error {
        if error.isUnauthorized || error.isConflict {
          self.accessToken = nil
          self.refreshToken = nil
          let userInfo = [NetworkingError.userInfoKey: error]
          DispatchQueue.main.async {
            NotificationCenter.default.post(name: API.didRefreshTokensNotification, object: self, userInfo: userInfo)
          }
        } else {
          for queuedRequest in self.queuedRequests {
            queuedRequest.1(object, response, error)
          }
        }
        HTTP.networkActivityCount -= self.queuedRequests.count-1
        HTTP.networkActivityIndicatorVisible = false
        self.queuedRequests.removeAll()
      } else {
        let dictionary = object! as! [String: String]
        self.accessToken = dictionary["access_token"]!
        self.refreshToken = dictionary["refresh_token"]!
        DispatchQueue.main.async {
          NotificationCenter.default.post(name: API.didRefreshTokensNotification, object: self)
          self.sendQueuedRequests()
        }
      }
    }
    refreshAccessTokenDataTask!.resume()
  }

  private func sendQueuedRequests() {
    for request in queuedRequests {
      var (updatedRequest, completionHandler) = request
      updatedRequest.anw_setAccessToken(accessToken!)
      self.baseDataTask(with: updatedRequest) { object, response, error in
        completionHandler(object, response, error)
        HTTP.networkActivityIndicatorVisible = false
      }.resume()
    }
  }

  open func baseDataTask(with request: URLRequest, completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Swift.Void) -> URLSessionDataTask {
    return session.dataTask(with: request) { data, response, error in
      let object: Any?
      let httpResponse = response as! HTTPURLResponse?
      let networkingError: NetworkingError?

      if let error = error {
        object = nil
        networkingError = NetworkingError(error: error as NSError)
      } else {
        if let jsonObject = self.parseJSON(with: data!) {
          object = jsonObject
        } else {
          object = self.errorMessageDictionary(with: data!)
        }
        if httpResponse!.anw_hasErrorStatusCode {
          let dictionary = object! as! [String: String]
          networkingError = NetworkingError(dictionary: dictionary, response: httpResponse!)
        } else {
          networkingError = nil
        }
      }

      completionHandler(object, httpResponse, networkingError)
    }
  }

  private func parseJSON(with data: Data) -> Any? {
    try? JSONSerialization.jsonObject(with: data)
  }

  private func errorMessageDictionary(with data: Data) -> [String: String] {
    if String(data: data, encoding: .utf8)!.range(of: "maintenance-mode") != nil {
      return ["message": "The server is undergoing maintenance. Please try again later."]
    } else {
      return ["message": "The server encountered an unexpected error."]
    }
  }

  public static let didRefreshTokensNotification = Notification.Name("APIDidRefreshTokensNotification")
}

open class HTTP {
  fileprivate static var networkActivityCount: Int = 0

  public static var networkActivityIndicatorVisible: Bool {
    get { return networkActivityCount > 0 }
    set(visible) {
      networkActivityCount += visible ? 1 : -1
      precondition(networkActivityCount >= 0)
      DispatchQueue.main.async {
        UIApplication.shared.isNetworkActivityIndicatorVisible = (networkActivityCount > 0)
      }
    }
  }

  public static func request(_ HTTPMethod: String, _ url: Foundation.URL, _ fields: [String: String]? = nil, _ JPEGData: Data? = nil) -> URLRequest {
    var request = URLRequest(url: url)
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
  // As curl does, let front-end developers URL encode names & values.
  public static func formHTTPBody(withFields fields: [String: String]) -> Data {
    var bodyArray = [String]()
    for (name, value) in fields {
      bodyArray.append("\(name)=\(value.anw_addingFormURLEncoding)")
    }
    return bodyArray.joined(separator: "&").data(using: .utf8)!
  }

  private static func multipartBoundary() -> String {
    return "-----AcaniFormBoundary" + String.anw_random(withLength: 16)
  }

  private static func multipartBodyData(_ boundary: String, _ fields: [String: String]? = nil, _ JPEGData: Data) -> Data {
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

extension URLRequest {
  public mutating func anw_setBasicAuth(with credentials: String) {
    let encodedCredentials = credentials.data(using: .utf8)!.base64EncodedString()
    setValue("Basic "+encodedCredentials, forHTTPHeaderField: "Authorization")
  }

  public mutating func anw_setAccessToken(_ accessToken: String) {
    setValue("Bearer "+accessToken, forHTTPHeaderField: "Authorization")
  }
}

extension HTTPURLResponse {
  public var anw_hasErrorStatusCode: Bool { return statusCode < 200 || 299 < statusCode }

  public var anw_isUserUnauthenticated: Bool {
    if statusCode != 401 { return false }
    let wwwHeader = allHeaderFields["Www-Authenticate"]! as! String
    return wwwHeader.starts(with: "Bearer ")
  }
}

extension String {
  public static func anw_random(withLength length: Int) -> String {
    let alphabet = "-_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" // 64 characters
    return String((0..<length).map { _ -> Character in
      return alphabet[alphabet.index(alphabet.startIndex, offsetBy: Int(arc4random_uniform(64)))]  // <^ connected
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
  public let isAPIError: Bool
  public let code: Int
  public let title: String
  public let message: String?
  public let type: String?
  public var isUnauthorized: Bool { return isAPIError && code == 401 }
  public var isForbidden: Bool { return isAPIError && code == 403 }
  public var isNotFound: Bool { return isAPIError && code == 404 }
  public var isConflict: Bool { return isAPIError && code == 409 }

  public init(error: NSError) {
    isAPIError = false
    code = error.code
    title = ""
    message = error.localizedDescription
    type = nil
  }

  public init(statusCode: Int) {
    isAPIError = true
    code = statusCode
    title = ""
    message = nil
    type = nil
  }

  public init(dictionary: [String: String], response: HTTPURLResponse) {
    isAPIError = true
    code = response.statusCode
    title = dictionary["title"] ?? ""
    message = dictionary["message"]
    type = dictionary["type"]
  }

  public static let userInfoKey = "NetworkingErrorUserInfoKey"
}

import Alerts

public func alertNetworkingError(_ error: NetworkingError, handler: ((UIAlertAction) -> Swift.Void)? = nil) {
  alertTitle(error.title, message: error.message, handler: handler)
}
