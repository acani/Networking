import UIKit

open class API {
  public let session: URLSession
  public let baseURL: URL
  public let versionPath: String?
  public let credentials: String
  open var accessToken: String?
  open var refreshToken: String?
  weak var refreshSessionDataTask: URLSessionDataTask?
  open var queuedRequests: [(URLRequest, (Any?, HTTPURLResponse?, NetworkingError?) -> Void)]

  public init(baseURL: URL, versionPath: String? = nil, credentials: String) {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 33
    session = URLSession(configuration: configuration)
    self.baseURL = baseURL
    self.versionPath = versionPath
    self.credentials = credentials
    queuedRequests = []
  }

  open func request(
    _ httpMethod: String,
    _ path: String,
    _ fields: [String: String]? = nil,
    _ jpegData: Data? = nil,
    authenticated: Bool = false
  ) -> URLRequest {
    let versionedPath = versionPath != nil ? versionPath!+path : path
    let requestURL = URL(string: versionedPath, relativeTo: baseURL)!
    var request = HTTP.request(httpMethod, requestURL, fields, jpegData)
    if !authenticated {
      request.anw_setBasicAuth(with: credentials)
    } else {
      request.anw_setAccessToken(accessToken!)
    }
    return request
  }

  open func dataTask(
    with request: URLRequest,
    completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Void
  ) -> URLSessionDataTask {
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
            self.refreshSessionAndRetryRequest(request, completionHandler: completionHandler)
            return
          }
        } else {
          object = self.errorMessageDictionary(with: data!)
        }
        if httpResponse!.anw_hasErrorStatusCode {
          let statusCode = httpResponse!.statusCode
          if let dictionary = object! as? [String: String] {
            networkingError = NetworkingError(statusCode: statusCode, dictionary: dictionary)
          } else {
            networkingError = NetworkingError(statusCode: statusCode)
          }
        } else {
          networkingError = nil
        }
      }

      completionHandler(object, httpResponse, networkingError)
    }
  }

  private func refreshSessionAndRetryRequest(
    _ request: URLRequest,
    completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Void
  ) {
    queuedRequests.append((request, completionHandler))
    let isCompleted = refreshSessionDataTask == nil || refreshSessionDataTask!.state == .completed
    guard isCompleted else { return }
    let refreshRequest = self.request("PUT", "/sessions", ["refresh_token": refreshToken!])
    refreshSessionDataTask = baseDataTask(with: refreshRequest) { object, response, error in
      if let error = error {
        if error.isUnauthorized || error.isConflict {
          self.accessToken = nil
          self.refreshToken = nil
          let userInfo = [NetworkingError.userInfoKey: error]
          DispatchQueue.main.async {
            NotificationCenter.default
              .post(name: API.didRefreshTokensNotification, object: self, userInfo: userInfo)
          }
        } else {
          for queuedRequest in self.queuedRequests {
            queuedRequest.1(object, response, error)
          }
        }
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
    refreshSessionDataTask!.resume()
  }

  private func sendQueuedRequests() {
    for request in queuedRequests {
      var (updatedRequest, completionHandler) = request
      updatedRequest.anw_setAccessToken(accessToken!)
      self.baseDataTask(with: updatedRequest) { object, response, error in
        completionHandler(object, response, error)
      }.resume()
    }
  }

  open func baseDataTask(
    with request: URLRequest,
    completionHandler: @escaping (Any?, HTTPURLResponse?, NetworkingError?) -> Void
  ) -> URLSessionDataTask {
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
          networkingError = NetworkingError(
            statusCode: httpResponse!.statusCode,
            dictionary: (object! as! [String: String])
          )
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

  public static let didRefreshTokensNotification =
    Notification.Name("APIDidRefreshTokensNotification")
}

open class HTTP {
  public static func request(
    _ httpMethod: String,
    _ url: Foundation.URL,
    _ fields: [String: String]? = nil,
    _ jpegData: Data? = nil
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = httpMethod

    let contentType = "Content-Type"
    if jpegData == nil {
      if let fields = fields {
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: contentType)
        request.httpBody = formHTTPBody(withFields: fields)
      }
    } else {
      let boundary = multipartBoundary()
      request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: contentType)
      request.httpBody = multipartBodyData(boundary, fields, jpegData!)
    }

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

  private static func multipartBodyData(
    _ boundary: String,
    _ fields: [String: String]? = nil,
    _ JPEGData: Data
  ) -> Data {
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
    let alphabet = [
      "-",
      "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
      "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
      "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
      "_",
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
      "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    ]
    return (0..<length).map { _ -> String in alphabet.randomElement()! }.joined()
  }

  // http://www.w3.org/TR/html5/forms.html#application/x-www-form-urlencoded-encoding-algorithm
  public var anw_addingFormURLEncoding: String {
    var characterSet = CharacterSet.urlQueryAllowed
    characterSet.insert(charactersIn: " ")
    return addingPercentEncoding(withAllowedCharacters: characterSet)!
      .replacingOccurrences(of: " ", with: "+")
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

  public init(statusCode: Int, dictionary: [String: String]? = nil) {
    isAPIError = true
    code = statusCode
    title = dictionary?["title"] ?? ""
    message = dictionary?["message"]
    type = dictionary?["type"]
  }

  public static let userInfoKey = "NetworkingErrorUserInfoKey"
}

import Alerts

public func alertNetworkingError(
  _ error: NetworkingError,
  handler: ((UIAlertAction) -> Void)? = nil
) {
  alertTitle(error.title, message: error.message, handler: handler)
}
